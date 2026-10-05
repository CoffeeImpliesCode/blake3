// SPDX-License-Identifier: CC0-1.0 OR Apache-2.0 OR Apache-2.0 WITH LLVM-exception
//
//! Deeper regressions for the loader's shared lifecycle, against a real
//! provider.
//!
//! `runtime/load_tests.zig` covers one lifecycle end to end: an empty and an
//! oversized request, a path that is not there, a file that is not BLAKE3, then
//! eight threads arriving at one first load. What is left is the part of the
//! contract that needs an attempt to be held open while it is arranged: who gets
//! which result when several callers are attached, what a consumer can observe
//! while validation has not finished, and what the platform still holds once an
//! attempt is over. That is what this file is for.
//!
//! ## Every provider here is a real BLAKE3
//!
//! `BLAKE3_TEST_PROVIDER` names the shared object this package built, and it is
//! the only provider these cases load. No export is faked and nothing is
//! interposed: every answer checked is an error the loader returned, a readiness
//! flag or retained request the loader published, a digest upstream published,
//! or what the platform's own loader reports it is holding. Nothing is skipped
//! when the variable is missing -- a case that cannot name a provider has
//! nothing to say, and passing would mean nothing.
//!
//! The two cases that ask the platform about a handle load a copy of that same
//! object out of a private directory, because the question "is this attempt's
//! candidate still open" has one answer only when nothing else in the process is
//! holding that file. The bytes are the separately built library, unchanged.
//!
//! ## The interleaving invariant
//!
//! What is under test is *when* a caller arrives relative to an attempt, so
//! nothing here rests on a sleep or on a lucky schedule:
//!
//!   1. The fixture scripts what each attempt's `validate` will answer, and
//!      gives the first attempt somewhere to park inside validation.
//!   2. The attempt parks: every symbol is resolved and the real checks have run
//!      over the table it is about to publish, and it cannot finish until the
//!      fixture releases it.
//!   3. The fixture starts the other callers and blocks until the loader's own
//!      bookkeeping says they are attached. The control observes the production
//!      `wait` to know when to look; the loader's waiter count, read under the
//!      production lock it is kept under, says what is true.
//!   4. Only then is the attempt released. Every caller that was attached is
//!      therefore decided by that attempt, and nothing one of them returns can be
//!      the result of a later attempt.
//!
//! ## What the fixture decides, and what it does not
//!
//! `validate` is the library's own post-resolution check, and this file's
//! version does the real thing first: `blake3_version()` through the table, and
//! the digest of the empty input through `init`, `update` and `finalize`,
//! compared with the vector upstream published. Only after that does the fixture
//! answer. That is what lets the refusal cases assert the digest as well: a
//! refusal there is always a refusal of a real, working table.
//!
//! ## One configured instance per case
//!
//! A configured module has one table for the life of the process and no reset,
//! so each case gets its own instance type and with it its own table, readiness
//! flag, loader state and control. No case shares state with another and no case
//! depends on the order they run in.
//!
//! ## What this file does not reach
//!
//! * The window between an attempt publishing its result and its record being
//!   cleared is not reachable from outside the loader, which holds its own lock
//!   across it. What is covered instead is the consequence: every caller
//!   attached to a failed attempt must report that failure, and the next call
//!   must start a fresh attempt. A record released too early breaks both.
//! * The handle cases ask the platform what it holds: Linux answers from
//!   `/proc/self/maps`, Darwin from the dyld image list, Windows from
//!   `GetModuleHandleW`. A target with a dynamic loader and none of those three
//!   gets the readiness and request assertions and one printed line saying the
//!   handle was not observed. A target with no dynamic loader at all is not
//!   built here: `rt.supported_target` is false there and there is nothing to
//!   ask.

const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const testing = std.testing;

const rt = @import("rt");
const library = @import("library");
const dispatch = @import("dispatch");

/// Every way a case can fail to arrange what it set out to arrange, and every
/// way a case can find the loader contradicting its own contract.
const Arrangement = error{
    /// An attempt never reached validation, so there was nothing to attach to.
    AttemptNeverReachedValidation,
    /// The loader made fewer `wait` calls than the case asked to observe.
    NoCallerAttached,
    /// No attempt was in flight when a caller was expected to be attached.
    NoAttemptInFlight,
    /// The loader's own waiter count says the callers did not attach.
    CallersWereNotAttached,
    /// Ready, but reporting no request, which the contract says cannot happen.
    NoRetainedRequest,
    /// The reentrant call this case was built around never happened.
    NoReentrantCall,
    /// A caller that was supposed to be refused without waiting never came back.
    NoCallerReturned,
};

// ---------------------------------------------------------------------------
// The provider
// ---------------------------------------------------------------------------

/// A shared object exporting the nine entry points of `c/blake3.h`.
const provider_variable = "BLAKE3_TEST_PROVIDER";

/// That object, copied into `buffer`.
///
/// Copied because the loader keeps its own copy of a request for the life of the
/// process and compares later requests against it, so a caller may hand it any
/// bytes it likes, including bytes it is finished with. Each case passes its own
/// buffer, so no case can overwrite the bytes another case's request named.
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

/// A private copy of `from` in `dir` under `name`, and its absolute path.
///
/// The caller owns the returned path. A copy is what makes the handle cases
/// answerable: the provider's own path is loaded and kept by then, so a
/// question about whether *this* attempt's candidate is still open would
/// otherwise be answered by somebody else's handle.
fn copyProvider(dir: Io.Dir, name: []const u8, from: []const u8) ![:0]u8 {
    try Io.Dir.cwd().copyFile(from, dir, name, testing.io, .{});
    return dir.realPathFileAlloc(testing.io, name, testing.allocator);
}

/// Upstream's published digest of the empty input, read out of
/// `test_vectors/test_vectors.json`: the `input_len: 0` case, whose first 32
/// bytes are the digest and whose remaining bytes are extended output.
///
/// This is what a real, working BLAKE3 table answers, and it is stated here
/// rather than computed, so a table that resolved something else cannot agree
/// with it by accident.
const published_empty_digest = "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262";

/// The digest of the empty input, computed through a table the loader filled.
///
/// `init`, `update` and `finalize` are three of the nine entry points
/// `c/blake3.h:63-80` declares, called through the table exactly as a consumer
/// calls them through the facade.
fn digestThrough(dst: *const dispatch.Table) [dispatch.BLAKE3_OUT_LEN]u8 {
    var hasher: dispatch.blake3_hasher = undefined;
    var out: [dispatch.BLAKE3_OUT_LEN]u8 = undefined;
    dst.blake3_hasher_init(&hasher);
    dst.blake3_hasher_update(&hasher, "", 0);
    dst.blake3_hasher_finalize(&hasher, &out, out.len);
    return out;
}

// ---------------------------------------------------------------------------
// The gate, and the barrier it is arranged with
// ---------------------------------------------------------------------------

/// What one attempt's `validate` answers.
const Verdict = enum { accept, decline };

/// One scripted attempt: the answer, and whether the attempt parks at the gate
/// until the fixture releases it.
const Step = struct {
    verdict: Verdict = .accept,
    hold: bool = false,
};

const max_steps = 4;
const no_steps = [_]Step{.{}} ** max_steps;

/// A script in which only the attempts a case needs are scripted. Anything past
/// the list is the default, and an attempt arriving past the whole script is a
/// case that has lost track of its own attempts.
fn script(entries: []const Step) [max_steps]Step {
    var all = no_steps;
    if (entries.len > all.len) @panic("a case scripted more attempts than one script holds");
    @memcpy(all[0..entries.len], entries);
    return all;
}

/// Nothing holds: every attempt runs straight through the gate.
const no_gate = script(&.{.{}});

/// How many attached callers one case may wait for. A script names at most
/// `max_steps` attempts and no case attaches more callers than that to one.
const max_attachers = 8;

/// How long a fixture waits for an arrangement it asked for before deciding the
/// arrangement cannot happen.
///
/// A bound on being wrong, not on waiting. Nothing here decides an outcome by how
/// long it waited: every wait is a condition, and this only turns a caller that
/// never attaches from a hang into a failure the gate reports.
const arrangement_budget: Io.Timeout = .{
    .duration = .{ .raw = Io.Duration.fromSeconds(60), .clock = .real },
};

/// Counts the calls the loader made to the production `wait`, one slot each, so
/// a fixture can block until the n-th caller has attached instead of polling for
/// it.
///
/// Test-only, and only on the way past: the lock, the wake-up and the thread
/// identity are still the production ones, and this changes nothing about what
/// they do. What a case then asserts is never this count but what the attached
/// callers returned.
const WaitCounter = struct {
    index: std.atomic.Value(usize) = .init(0),
    slots: [max_attachers]Io.Event = [_]Io.Event{.unset} ** max_attachers,

    fn note(self: *WaitCounter, io: Io) void {
        const at = self.index.fetchAdd(1, .acq_rel);
        if (at < self.slots.len) self.slots[at].set(io);
    }

    /// Block until `n` calls have been noted.
    fn awaitAtLeast(self: *WaitCounter, io: Io, n: usize) Arrangement!void {
        if (n == 0) return;
        std.debug.assert(n <= self.slots.len);
        self.slots[n - 1].waitTimeout(io, arrangement_budget) catch |err| switch (err) {
            error.Timeout => {
                // An expired budget and a spurious wake-up look the same here,
                // so the counter decides, not the wake-up.
                if (self.index.load(.acquire) <= n - 1) return error.NoCallerAttached;
            },
            error.Canceled => unreachable,
        };
    }
};

/// Everything one case's instance lets its fixture drive.
const Control = struct {
    io: Io = undefined,
    steps: [max_steps]Step = no_steps,
    /// Attempts that have reached the gate, in order. One attempt at a time is
    /// the loader's own promise, so only the thread inside an attempt writes it.
    entered: usize = 0,
    arrived: Io.Event = .unset,
    released: Io.Event = .unset,
    waits: WaitCounter = .{},

    /// The request the attempt should call `load` with again, for the case about
    /// reentrancy, and what that call answered.
    reentrant: ?rt.LoadSource = null,
    reentrant_seen: ?rt.LoadError!void = null,

    /// What the real table answered while the attempt was in validation.
    version_len: usize = 0,
    digest: [dispatch.BLAKE3_OUT_LEN]u8 = @splat(0),

    /// The library's own check, over the table the loader has just filled, and
    /// then the fixture's answer.
    fn check(self: *Control, dst: *const dispatch.Table) ?[]const u8 {
        // The check `runtime/library.zig` makes, on the same table, for the same
        // reason: an entry point that opens and returns nothing is not a library
        // this header describes.
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

    /// Arrive at the gate, and stay there until the fixture releases this
    /// attempt.
    ///
    /// What the real checks above found is recorded before the fixture's
    /// decision is taken, so a case can assert afterwards that a refusal was the
    /// fixture's and not the table's.
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

    /// Block until an attempt is parked at the gate.
    fn awaitArrival(self: *Control) Arrangement!void {
        self.arrived.waitTimeout(self.io, arrangement_budget) catch |err| switch (err) {
            error.Timeout => return error.AttemptNeverReachedValidation,
            error.Canceled => unreachable,
        };
    }

    /// Let every attempt that reached the gate continue.
    fn release(self: *Control) void {
        self.released.set(self.io);
    }

    /// Assert that the real checks over the resolved table found a real BLAKE3.
    fn expectRealProvider(self: *const Control) !void {
        try testing.expect(self.version_len > 0);
        try testing.expectEqualStrings(
            published_empty_digest,
            &std.fmt.bytesToHex(self.digest, .lower),
        );
    }
};

// ---------------------------------------------------------------------------
// The configured instance, one per case
// ---------------------------------------------------------------------------

/// Which case an instance belongs to. The tag exists because the loader's
/// configuration interface reaches its table and its readiness flag without a
/// receiver, so each case's copy of that state needs an address the compiler can
/// name, and a distinct type is the only way to get one.
const Tag = enum {
    attached_success,
    attached_failure,
    unpublished_attempt,
    reentrant_call,
    conflicting_request,
    closed_candidate,
    retained_handle,
};

/// One configured instance: the loader's contract for one table, the fixture
/// control it is arranged with, and the production synchronization it uses.
fn Instance(comptime tag: Tag) type {
    return struct {
        const case_tag = tag;
        const Self = @This();
        const Config = Conf(Self);

        var table: dispatch.Table = undefined;
        var flag: rt.Ready = .{};
        var loader: rt.Loader(Config) = .{};
        var control: Control = .{};

        /// Script the attempts this instance will see, and give the first one
        /// somewhere to park. Called before any thread exists.
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

        /// The table this instance publishes into, and the only table a case
        /// reads.
        pub fn tablePtr() *dispatch.Table {
            return &table;
        }

        /// The one library-specific check, run after every symbol resolved and
        /// before anything is published.
        pub fn validate(dst: *const dispatch.Table) ?[]const u8 {
            const refusal = control.check(dst);
            if (control.reentrant) |source| {
                // The same thread, still inside the attempt, with no loader lock
                // held: this is the call `ReentrantLoad` exists for.
                control.reentrant_seen = loader.load(source);
            }
            return refusal;
        }

        /// One call to the production `wait`, reported to the fixture.
        pub fn noteWait() void {
            control.waits.note(control.io);
        }

        /// Block until an attempt is parked at the gate.
        pub fn awaitArrival() Arrangement!void {
            try control.awaitArrival();
        }

        /// Block until `n` callers are attached to the attempt in flight.
        ///
        /// The control's barrier says when to look, and then the loader's own
        /// waiter count, read under the production lock it is kept under, says
        /// what is true. Only the arrangement is checked here: what those callers
        /// return is what a case asserts.
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

/// The loader's configuration for one instance: the same descriptor the facade
/// uses, over that instance's own table and readiness flag.
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

/// The production synchronization with one addition: every `wait` is also
/// reported to the fixture.
///
/// `lock`, `unlock`, `broadcast` and `threadSelf` are the production
/// implementation, unchanged and unwrapped, so the loader's mutual exclusion,
/// its wake-ups and its reentrancy check are the ones this SDK actually ships.
/// Only the wait is announced, and only so that a fixture can block until a
/// caller has attached.
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

// ---------------------------------------------------------------------------
// One caller
// ---------------------------------------------------------------------------

/// One thread's whole job: call `load` once and keep what came back.
///
/// `done` is set when this caller's `load` has returned, so a fixture can read
/// that without waiting and can also block on it with a bound: a caller that
/// was supposed to be refused without waiting, and did not come back, fails its
/// own case instead of hanging the gate. `outcome` is only ever read once the
/// caller is known to have returned.
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

        /// Block until this caller has come back.
        pub fn awaitReturn(self: *Self) Arrangement!void {
            self.done.waitTimeout(self.io, arrangement_budget) catch |err| switch (err) {
                error.Timeout => if (!self.done.isSet()) return error.NoCallerReturned,
                error.Canceled => unreachable,
            };
        }
    };
}

/// What a consumer can see once the module has loaded: the request that
/// succeeded, the readiness flag, and the published table hashing what upstream
/// published.
fn expectPublished(comptime Case: type, path: []const u8) !void {
    const retained = Case.loadedSource() orelse return error.NoRetainedRequest;
    try testing.expectEqualStrings(path, retained.path);
    try testing.expect(Case.ready().isReady());
    try testing.expectEqualStrings(
        published_empty_digest,
        &std.fmt.bytesToHex(digestThrough(Case.tablePtr()), .lower),
    );
}

// ---------------------------------------------------------------------------
// What the platform's own loader is still holding
// ---------------------------------------------------------------------------

/// How this target can be asked whether it holds a file.
const route = switch (builtin.os.tag) {
    // The kernel's list of what this process has mapped.
    .linux => .proc_maps,
    // The list of images dyld has loaded for this process.
    .macos, .ios, .tvos, .watchos, .visionos => .dyld_images,
    // The loader's module list, which a module appears in until the last handle
    // to it is closed.
    .windows => .module_handle,
    // A target with a dynamic loader and none of the routes above: the case
    // that asked says so instead of guessing.
    else => .none,
};

/// Whether the platform's loader is still holding `path`, asked without asking
/// this loader anything. A dynamic loader keeps a file until the last handle to
/// it is closed, so a candidate closed on failure is gone from the answer and a
/// candidate kept for the life of the process is in it.
///
/// Null where this target offers no route, which is reported rather than guessed
/// about.
///
/// The route is a comptime-known constant and each probe is chosen with a
/// comptime condition, the way `runtime/loader.zig` chooses its platform
/// layer: the probe for another target is never analysed on this one, so a
/// Darwin call is never emitted into a Linux binary and `kernel32` is never
/// linked where it does not exist.
fn platformHolds(path: []const u8) ?bool {
    if (route == .proc_maps) return mappedIntoThisProcess(path);
    if (route == .dyld_images) return loadedIntoThisProcess(path);
    if (route == .module_handle) return moduleLoaded(path);
    return null;
}

/// One printed line naming what this case could not observe, so that a run which
/// asserts less says which part and why.
fn reportUnobserved(what: []const u8, path: []const u8) void {
    std.debug.print(
        "runtime/core_tests.zig: {s} was not observed for {s} on {s}: this target has a " ++
            "dynamic loader and no route here that can ask. The readiness and request " ++
            "assertions still ran.\n",
        .{ what, path, @tagName(builtin.os.tag) },
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
        // A mapped file's line ends with its path, so a match that is not at the
        // end of a line is a different file that happens to contain the name.
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
        // dyld reports the path it resolved, which need not be the path that was
        // asked for. The name is enough here: this case chose it, in a directory
        // this case created.
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

// ---------------------------------------------------------------------------
// The cases
// ---------------------------------------------------------------------------

test "a caller attached to a successful attempt gets that attempt's success" {
    const Case = Instance(.attached_success);
    var buffer: [4096]u8 = undefined;
    const path = providerPath(&buffer);

    Case.arm(testing.io, script(&.{.{ .hold = true }}), null);

    var attempt: Worker(Case) = .{};
    var waiters: [3]Worker(Case) = @splat(.{});
    attempt.source = .{ .path = path };
    try attempt.start(testing.io);

    // The attempt is inside validation with every symbol resolved and its checks
    // run; it cannot publish or fail until the fixture releases it.
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

    // Each of them reported that attempt's result and not their own: a caller's
    // own attempt would have been a second open of a file the first one already
    // holds, and a caller that got one of those instead would report something
    // other than the success the attempt published.
    try attempt.outcome;
    for (&waiters) |*waiter| try waiter.outcome;

    try expectPublished(Case, path);
}

test "a caller attached to a failed attempt gets that failure, and the retry is the caller's" {
    const Case = Instance(.attached_failure);
    var buffer: [4096]u8 = undefined;
    const path = providerPath(&buffer);

    // The first attempt is scripted to be refused and the caller's own retry is
    // scripted to be accepted, so a caller that reported the retry rather than
    // the attempt it attached to would be visible.
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

    // The refusal published nothing: not ready, no request, and a table the
    // consumer has no way to reach.
    try testing.expect(!Case.ready().isReady());
    try testing.expect(Case.loadedSource() == null);
    try Case.expectRealProvider();

    // Nothing retries by itself. This call is the retry, and it succeeds.
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

    // Every symbol is resolved, but an attempt that has not validated has
    // published neither the request nor the readiness a routed call needs.
    try testing.expect(Case.ready().state() == .loading);
    try testing.expect(!Case.ready().isReady());
    try testing.expect(Case.loadedSource() == null);

    reader.source = .{ .path = path };
    try reader.start(testing.io);
    try Case.awaitAttached(1);

    // The reader is attached to that attempt and the attempt is still held, so
    // the reader cannot have come back.
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

    // No gate: the point of this case is the call the attempt makes into `load`
    // itself, on its own thread, with the loader holding no lock.
    Case.arm(testing.io, no_gate, .{ .path = path });

    try Case.load(.{ .path = path });

    const seen = Case.reentrantSeen() orelse return error.NoReentrantCall;
    try testing.expectError(error.ReentrantLoad, seen);

    // The attempt that call interrupted finished normally.
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

    // The attempt in flight is committed to its own provider, so there is
    // nothing for a request naming another one to wait for: it is refused while
    // the attempt is still open, not after it, and it did not attach.
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

    // The candidate resolved every symbol and hashed correctly, and was still
    // closed: nothing it published survives, and nothing of it is left loaded.
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
    // The provider remains mapped until process exit. The driver removes this
    // private cache copy only after the test process exits.
    const copy = try copyProvider(directory.dir, "libblake3-retained-handle.so", path);
    defer testing.allocator.free(copy);

    Case.arm(testing.io, no_gate, null);

    try Case.load(.{ .path = copy });
    try expectPublished(Case, copy);

    // The published table holds addresses inside that object, so the handle
    // behind them has to stay: this is what the process keeps from now on.
    if (platformHolds(copy)) |held| {
        try testing.expect(held);
    } else {
        reportUnobserved("a retained handle", copy);
    }
}
