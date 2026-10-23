// SPDX-License-Identifier: CC0-1.0 OR Apache-2.0 OR Apache-2.0 WITH LLVM-exception

const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const testing = std.testing;

const rt = @import("rt");
const library = @import("library");
const dispatch = @import("dispatch");

const Arrangement = error{
    AttemptNeverReachedValidation,
    NoCallerAttached,
    NoAttemptInFlight,
    CallersWereNotAttached,
    NoRetainedRequest,
    NoReentrantCall,
    NoCallerReturned,
};

const provider_variable = "BLAKE3_TEST_PROVIDER";

/// Returns the provider path in the caller's buffer.
fn providerPath(buffer: []u8) []const u8 {
    const value = testing.environ.getAlloc(testing.allocator, provider_variable) catch @panic(
        "runtime/core_tests.zig: " ++ provider_variable ++
            " could not be read from the environment. These cases load a real " ++
            "provider; without one there is nothing to test and passing would mean nothing.",
    );
    defer testing.allocator.free(value);
    if (value.len == 0 or value.len > buffer.len) @panic(
        "runtime/core_tests.zig: " ++ provider_variable ++
            " is empty or does not fit in one path buffer.",
    );
    @memcpy(buffer[0..value.len], value);
    return buffer[0..value.len];
}

/// Returns the absolute path of a private provider copy; the caller owns the path.
fn copyProvider(dir: Io.Dir, name: []const u8, from: []const u8) ![:0]u8 {
    try Io.Dir.cwd().copyFile(from, dir, name, testing.io, .{});
    return dir.realPathFileAlloc(testing.io, name, testing.allocator);
}

/// Upstream's published empty-input digest (the first 32 bytes of its extended output).
const published_empty_digest = "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262";

/// Hashes the empty input through a resolved table.
fn digestThrough(dst: *const dispatch.Table) [dispatch.BLAKE3_OUT_LEN]u8 {
    var hasher: dispatch.blake3_hasher = undefined;
    var out: [dispatch.BLAKE3_OUT_LEN]u8 = undefined;
    dst.blake3_hasher_init(&hasher);
    dst.blake3_hasher_update(&hasher, "", 0);
    dst.blake3_hasher_finalize(&hasher, &out, out.len);
    return out;
}

const Verdict = enum { accept, decline };

const Step = struct {
    verdict: Verdict = .accept,
    hold: bool = false,
};

const max_steps = 4;
const no_steps: [max_steps]Step = @splat(.{});

/// Fills unspecified attempts with defaults; panics if the script exceeds `max_steps`.
fn script(entries: []const Step) [max_steps]Step {
    var all = no_steps;
    if (entries.len > all.len) @panic("a case scripted more attempts than one script holds");
    @memcpy(all[0..entries.len], entries);
    return all;
}

const no_gate = script(&.{.{}});

/// Maximum number of callers a case can attach.
const max_attachers = 8;

const arrangement_budget: Io.Timeout = .{
    .duration = .{ .raw = Io.Duration.fromSeconds(60), .clock = .real },
};

/// Test-only counter on the production wait path; fixtures use it to await attachment without polling.
const WaitCounter = struct {
    index: std.atomic.Value(usize) = .init(0),
    slots: [max_attachers]Io.Event = @splat(.unset),

    fn note(self: *WaitCounter, io: Io) void {
        const at = self.index.fetchAdd(1, .acq_rel);
        if (at < self.slots.len) self.slots[at].set(io);
    }

    fn awaitAtLeast(self: *WaitCounter, io: Io, n: usize) Arrangement!void {
        if (n == 0) return;
        std.debug.assert(n <= self.slots.len);
        self.slots[n - 1].waitTimeout(io, arrangement_budget) catch |err| switch (err) {
            error.Timeout => {
                // Recheck the counter: a wake-up may be spurious or timed out.
                if (self.index.load(.acquire) <= n - 1) return error.NoCallerAttached;
            },
            error.Canceled => unreachable,
        };
    }
};

const Control = struct {
    io: Io = undefined,
    steps: [max_steps]Step = no_steps,
    /// Only the thread inside an attempt writes this count.
    entered: usize = 0,
    arrived: Io.Event = .unset,
    released: Io.Event = .unset,
    waits: WaitCounter = .{},

    reentrant: ?rt.LoadSource = null,
    reentrant_seen: ?rt.LoadError!void = null,

    version_len: usize = 0,
    digest: [dispatch.BLAKE3_OUT_LEN]u8 = @splat(0),

    fn check(self: *Control, dst: *const dispatch.Table) ?[]const u8 {
        // Match the runtime library check: reject an empty version before hashing.
        const version = dst.blake3_version();
        if (version == null or version[0] == 0) {
            return "blake3_version() returned null or an empty string";
        }
        self.version_len = std.mem.span(version).len;
        self.digest = digestThrough(dst);

        return switch (self.arrive()) {
            .accept => null,
            .decline => "this attempt was declined by the fixture, on purpose",
        };
    }

    /// Records the real checks before taking the fixture's verdict.
    fn arrive(self: *Control) Verdict {
        if (self.entered == self.steps.len) @panic(
            "runtime/core_tests.zig: a case ran more load attempts than it scripted",
        );
        const step = self.steps[self.entered];
        self.entered += 1;
        self.arrived.set(self.io);
        if (step.hold) self.released.waitUncancelable(self.io);
        return step.verdict;
    }

    fn awaitArrival(self: *Control) Arrangement!void {
        self.arrived.waitTimeout(self.io, arrangement_budget) catch |err| switch (err) {
            error.Timeout => return error.AttemptNeverReachedValidation,
            error.Canceled => unreachable,
        };
    }

    fn release(self: *Control) void {
        self.released.set(self.io);
    }

    fn expectRealProvider(self: *const Control) !void {
        try testing.expect(self.version_len > 0);
        try testing.expectEqualStrings(
            published_empty_digest,
            &std.fmt.bytesToHex(self.digest, .lower),
        );
    }
};

/// A distinct tag gives each case its own loader state.
const Tag = enum {
    attached_success,
    attached_failure,
    unpublished_attempt,
    reentrant_call,
    conflicting_request,
    closed_candidate,
    retained_handle,
};

fn Instance(comptime tag: Tag) type {
    return struct {
        const case_tag = tag;
        const Self = @This();
        const Config = Conf(Self);

        var table: dispatch.Table = undefined;
        var flag: rt.Ready = .{};
        var loader: rt.Loader(Config) = .{};
        var control: Control = .{};

        /// Configures the instance before worker threads start.
        pub fn arm(io: Io, steps: [max_steps]Step, reentrant: ?rt.LoadSource) void {
            control = .{ .io = io, .steps = steps, .reentrant = reentrant };
        }

        pub fn load(source: rt.LoadSource) rt.LoadError!void {
            return loader.load(source);
        }

        pub fn loadedSource() ?rt.LoadSource {
            return loader.loadedSource();
        }

        pub fn ready() *rt.Ready {
            return &flag;
        }

        pub fn tablePtr() *dispatch.Table {
            return &table;
        }

        /// Validates the resolved table before the loader publishes it.
        pub fn validate(dst: *const dispatch.Table) ?[]const u8 {
            const refusal = control.check(dst);
            if (control.reentrant) |source| {
                // Reenter on the attempt thread after the loader releases its lock.
                control.reentrant_seen = loader.load(source);
            }
            return refusal;
        }

        pub fn noteWait() void {
            control.waits.note(control.io);
        }

        pub fn awaitArrival() Arrangement!void {
            try control.awaitArrival();
        }

        /// Waits for n callers to attach, then checks the loader's waiter count under its lock.
        pub fn awaitAttached(n: usize) Arrangement!void {
            try control.waits.awaitAtLeast(control.io, n);
            library.Sync.lock();
            defer library.Sync.unlock();
            const attempt = loader.attempt orelse return error.NoAttemptInFlight;
            if (attempt.waiters < n) return error.CallersWereNotAttached;
        }

        pub fn attachedWaiters() usize {
            library.Sync.lock();
            defer library.Sync.unlock();
            const attempt = loader.attempt orelse return 0;
            return attempt.waiters;
        }

        pub fn release() void {
            control.release();
        }

        pub fn expectRealProvider() !void {
            try control.expectRealProvider();
        }

        pub fn reentrantSeen() ?rt.LoadError!void {
            return control.reentrant_seen;
        }
    };
}

fn Conf(comptime owner: type) type {
    return struct {
        pub const library_name = "blake3";
        pub const table = dispatch.Table;
        pub const symbols = dispatch.symbols;
        pub const sync = ObservedSync(owner);

        pub fn tablePtr() *table {
            return owner.tablePtr();
        }

        pub fn ready() *rt.Ready {
            return owner.ready();
        }

        pub fn assign(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assign(index, dst, address);
        }

        pub fn validate(dst: *const table) ?[]const u8 {
            return owner.validate(dst);
        }
    };
}

/// Wraps only `wait` to report attachments; all other synchronization calls are production implementations.
fn ObservedSync(comptime owner: type) type {
    return struct {
        pub fn lock() void {
            library.Sync.lock();
        }

        pub fn unlock() void {
            library.Sync.unlock();
        }

        pub fn wait() void {
            owner.noteWait();
            library.Sync.wait();
        }

        pub fn broadcast() void {
            library.Sync.broadcast();
        }

        pub fn threadSelf() u64 {
            return library.Sync.threadSelf();
        }
    };
}

/// `outcome` is read only after `done` signals that `load` returned.
fn Worker(comptime Case: type) type {
    return struct {
        const Self = @This();

        thread: std.Thread = undefined,
        done: Io.Event = .unset,
        outcome: rt.LoadError!void = error.ReentrantLoad,
        source: rt.LoadSource = undefined,
        io: Io = undefined,

        pub fn start(self: *Self, io: Io) !void {
            self.io = io;
            self.thread = try std.Thread.spawn(.{}, run, .{self});
        }

        fn run(self: *Self) void {
            self.outcome = Case.load(self.source);
            self.done.set(self.io);
        }

        pub fn join(self: *Self) void {
            self.thread.join();
        }

        pub fn hasReturned(self: *const Self) bool {
            return self.done.isSet();
        }

        pub fn awaitReturn(self: *Self) Arrangement!void {
            self.done.waitTimeout(self.io, arrangement_budget) catch |err| switch (err) {
                error.Timeout => if (!self.done.isSet()) return error.NoCallerReturned,
                error.Canceled => unreachable,
            };
        }
    };
}

fn expectPublished(comptime Case: type, path: []const u8) !void {
    const retained = Case.loadedSource() orelse return error.NoRetainedRequest;
    try testing.expectEqualStrings(path, retained.path);
    try testing.expect(Case.ready().isReady());
    try testing.expectEqualStrings(
        published_empty_digest,
        &std.fmt.bytesToHex(digestThrough(Case.tablePtr()), .lower),
    );
}

const route = switch (builtin.target.os.tag) {
    .linux => .proc_maps,
    // The list of images dyld has loaded for this process.
    .macos, .ios, .tvos, .watchos, .visionos => .dyld_images,
    // Windows removes a module from the list after its last handle closes.
    .windows => .module_handle,
    else => .none,
};

/// Queries the platform loader directly; returns null when no probe exists.
/// Comptime selection keeps unavailable platform APIs out of the binary.
fn platformHolds(path: []const u8) ?bool {
    if (route == .proc_maps) return mappedIntoThisProcess(path);
    if (route == .dyld_images) return loadedIntoThisProcess(path);
    if (route == .module_handle) return moduleLoaded(path);
    return null;
}

fn reportUnobserved(what: []const u8, path: []const u8) void {
    std.debug.print(
        "runtime/core_tests.zig: {s} was not observed for {s} on {s}: this target has a " ++
            "dynamic loader and no route here that can ask. The readiness and request " ++
            "assertions still ran.\n",
        .{ what, path, @tagName(builtin.target.os.tag) },
    );
}

const max_maps_bytes = 4 * 1024 * 1024;

fn mappedIntoThisProcess(path: []const u8) ?bool {
    const file = Io.Dir.cwd().openFile(testing.io, "/proc/self/maps", .{}) catch |err| {
        std.debug.print("runtime/core_tests.zig: /proc/self/maps could not be opened: {s}\n", .{@errorName(err)});
        return null;
    };
    defer file.close(testing.io);
    var buffer: [4096]u8 = undefined;
    var reader = file.readerStreaming(testing.io, &buffer);
    const maps = reader.interface.allocRemaining(testing.allocator, .limited(max_maps_bytes)) catch |err| {
        std.debug.print(
            "runtime/core_tests.zig: /proc/self/maps could not be read: {s}\n",
            .{@errorName(err)},
        );
        return null;
    };
    defer testing.allocator.free(maps);

    var at: usize = 0;
    while (std.mem.indexOfPos(u8, maps, at, path)) |found| {
        // Require a line-ending match, not a path that merely contains the name.
        const end = found + path.len;
        if (end == maps.len or maps[end] == '\n') return true;
        at = end;
    }
    return false;
}

const dyld = struct {
    extern fn _dyld_image_count() u32;
    extern fn _dyld_get_image_name(index: u32) ?[*:0]const u8;
};

fn loadedIntoThisProcess(path: []const u8) ?bool {
    const name = Io.Dir.path.basename(path);
    var index: u32 = 0;
    while (index < dyld._dyld_image_count()) : (index += 1) {
        const image = dyld._dyld_get_image_name(index) orelse continue;
        // The test uses a private directory, so the resolved basename identifies its copy.
        if (std.mem.endsWith(u8, std.mem.span(image), name)) return true;
    }
    return false;
}

const kernel32 = struct {
    extern "kernel32" fn GetModuleHandleW(module_name: ?[*:0]const u16) ?*anyopaque;
};

fn moduleLoaded(path: []const u8) ?bool {
    var buffer: [Io.Dir.max_path_bytes]u16 = undefined;
    if (path.len > buffer.len) return null;
    const units = std.unicode.utf8ToUtf16Le(buffer[0..path.len], path) catch return null;
    buffer[units] = 0;
    return kernel32.GetModuleHandleW(buffer[0..units :0]) != null;
}

test "a caller attached to a successful attempt gets that attempt's success" {
    const Case = Instance(.attached_success);
    var buffer: [4096]u8 = undefined;
    const path = providerPath(&buffer);

    Case.arm(testing.io, script(&.{.{ .hold = true }}), null);

    var attempt: Worker(Case) = .{};
    var waiters: [3]Worker(Case) = @splat(.{});
    attempt.source = .{ .path = path };
    try attempt.start(testing.io);

    // The attempt cannot publish or fail until the fixture releases it.
    try Case.awaitArrival();

    for (&waiters) |*waiter| {
        waiter.source = .{ .path = path };
        try waiter.start(testing.io);
    }
    try Case.awaitAttached(waiters.len);
    try testing.expectEqual(waiters.len, Case.attachedWaiters());

    Case.release();

    attempt.join();
    for (&waiters) |*waiter| waiter.join();

    // Every attached caller receives the result published by this attempt.
    try attempt.outcome;
    for (&waiters) |*waiter| try waiter.outcome;

    try expectPublished(Case, path);
}

test "a caller attached to a failed attempt gets that failure, and the retry is the caller's" {
    const Case = Instance(.attached_failure);
    var buffer: [4096]u8 = undefined;
    const path = providerPath(&buffer);

    // The attached caller must receive the declined attempt's result, not its retry.
    Case.arm(testing.io, script(&.{ .{ .verdict = .decline, .hold = true }, .{} }), null);

    var attempt: Worker(Case) = .{};
    var waiters: [3]Worker(Case) = @splat(.{});
    attempt.source = .{ .path = path };
    try attempt.start(testing.io);
    try Case.awaitArrival();

    for (&waiters) |*waiter| {
        waiter.source = .{ .path = path };
        try waiter.start(testing.io);
    }
    try Case.awaitAttached(waiters.len);

    Case.release();

    attempt.join();
    for (&waiters) |*waiter| waiter.join();

    try testing.expectError(error.ValidationFailed, attempt.outcome);
    for (&waiters) |*waiter| try testing.expectError(error.ValidationFailed, waiter.outcome);

    // A refusal publishes neither readiness nor a retained request.
    try testing.expect(!Case.ready().isReady());
    try testing.expect(Case.loadedSource() == null);
    try Case.expectRealProvider();

    try Case.load(.{ .path = path });
    try expectPublished(Case, path);
}

test "nothing is published while validation is still running" {
    const Case = Instance(.unpublished_attempt);
    var buffer: [4096]u8 = undefined;
    const path = providerPath(&buffer);

    Case.arm(testing.io, script(&.{.{ .hold = true }}), null);

    var attempt: Worker(Case) = .{};
    var reader: Worker(Case) = .{};
    attempt.source = .{ .path = path };
    try attempt.start(testing.io);
    try Case.awaitArrival();

    // Before validation finishes, the request and readiness flag remain unpublished.
    try testing.expect(Case.ready().state() == .loading);
    try testing.expect(!Case.ready().isReady());
    try testing.expect(Case.loadedSource() == null);

    reader.source = .{ .path = path };
    try reader.start(testing.io);
    try Case.awaitAttached(1);

    // The reader is attached to the held attempt and cannot return yet.
    try testing.expect(!reader.hasReturned());
    try testing.expect(!Case.ready().isReady());
    try testing.expect(Case.loadedSource() == null);

    Case.release();

    attempt.join();
    reader.join();

    try attempt.outcome;
    try reader.outcome;
    try expectPublished(Case, path);
}

test "a call from the thread running the attempt is ReentrantLoad" {
    const Case = Instance(.reentrant_call);
    var buffer: [4096]u8 = undefined;
    const path = providerPath(&buffer);

    // Reenter on the attempt thread while the loader lock is released.
    Case.arm(testing.io, no_gate, .{ .path = path });

    try Case.load(.{ .path = path });

    const seen = Case.reentrantSeen() orelse return error.NoReentrantCall;
    try testing.expectError(error.ReentrantLoad, seen);

    try expectPublished(Case, path);
}

test "a different request while an attempt is in flight is ProviderMismatch" {
    const Case = Instance(.conflicting_request);
    var buffer: [4096]u8 = undefined;
    const path = providerPath(&buffer);

    var directory = testing.tmpDir(.{});
    defer directory.cleanup();
    const other = try copyProvider(directory.dir, "libblake3-other-request.so", path);
    defer testing.allocator.free(other);

    Case.arm(testing.io, script(&.{.{ .hold = true }}), null);

    var attempt: Worker(Case) = .{};
    var contender: Worker(Case) = .{};
    attempt.source = .{ .path = path };
    try attempt.start(testing.io);
    try Case.awaitArrival();

    contender.source = .{ .path = other };
    try contender.start(testing.io);
    try contender.awaitReturn();
    contender.join();

    // A different provider is refused while the active attempt is still in flight.
    try testing.expectError(error.ProviderMismatch, contender.outcome);
    try testing.expectEqual(@as(usize, 0), Case.attachedWaiters());

    Case.release();

    attempt.join();
    try attempt.outcome;
    try expectPublished(Case, path);
}

test "a candidate that fails validation is closed" {
    const Case = Instance(.closed_candidate);
    var buffer: [4096]u8 = undefined;
    const path = providerPath(&buffer);

    var directory = testing.tmpDir(.{});
    defer directory.cleanup();
    const copy = try copyProvider(directory.dir, "libblake3-closed-candidate.so", path);
    defer testing.allocator.free(copy);

    Case.arm(testing.io, script(&.{.{ .verdict = .decline }}), null);

    try testing.expectError(error.ValidationFailed, Case.load(.{ .path = copy }));
    try testing.expect(!Case.ready().isReady());
    try testing.expect(Case.loadedSource() == null);
    try Case.expectRealProvider();

    // The candidate passed validation, then failed; neither its state nor handle remains published.
    if (platformHolds(copy)) |held| {
        try testing.expect(!held);
    } else {
        reportUnobserved("a closed candidate", copy);
    }
}

test "a successful attempt keeps its handle and its table" {
    const Case = Instance(.retained_handle);
    var buffer: [4096]u8 = undefined;
    const path = providerPath(&buffer);

    var directory = testing.tmpDir(.{});
    defer directory.dir.close(testing.io);
    defer directory.parent_dir.close(testing.io);
    const copy = try copyProvider(directory.dir, "libblake3-retained-handle.so", path);
    defer testing.allocator.free(copy);

    Case.arm(testing.io, no_gate, null);

    try Case.load(.{ .path = copy });
    try expectPublished(Case, copy);

    // The published table contains pointers into the provider, so its handle must stay open.
    if (platformHolds(copy)) |held| {
        try testing.expect(held);
    } else {
        reportUnobserved("a retained handle", copy);
    }
}
