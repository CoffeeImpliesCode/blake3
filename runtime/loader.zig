// SPDX-License-Identifier: CC0-1.0 OR Apache-2.0 OR Apache-2.0 WITH LLVM-exception
const std = @import("std");
const builtin = @import("builtin");

/// A file path or system-loader name to load; the two forms are not interchangeable.
pub const LoadSource = union(enum) {
    /// Absolute file path; relative paths are rejected.
    path: []const u8,
    /// System-loader basename or SONAME; separators and NUL bytes are rejected.
    system: []const u8,
};

/// Errors returned for invalid requests, load failures and lifecycle conflicts.
pub const LoadError = error{
    /// Path or system name is empty.
    EmptySource,
    /// Request exceeds `max_source_len`; it is rejected, never truncated.
    SourceTooLong,
    /// Path is not absolute, system name has a separator, or input contains NUL.
    InvalidSource,
    /// The target has no dynamic library loader.
    UnsupportedTarget,
    /// The platform loader could not open the library or a dependency.
    OpenFailed,
    /// A required header symbol is missing; the candidate is closed.
    MissingSymbol,
    /// Library-specific validation rejected the candidate; nothing is published.
    ValidationFailed,
    /// A different provider is already loaded or in flight.
    ProviderMismatch,
    /// Called on the thread already inside an attempt; returns instead of waiting.
    ReentrantLoad,
};

/// Maximum retained request length in bytes.
pub const max_source_len = 32768;

/// Fixed-size request copy for process-lifetime identity checks; it allocates nothing.
const SourceRecord = struct {
    tag: enum(u8) { none = 0, path, system } = .none,
    len: u32 = 0,
    bytes: [max_source_len]u8 = undefined,

    /// Called under the loader lock after checking the request length.
    fn set(self: *SourceRecord, request: LoadSource) void {
        const text = switch (request) {
            .path => |p| p,
            .system => |s| s,
        };
        @memcpy(self.bytes[0..text.len], text);
        self.len = @intCast(text.len);
        self.tag = switch (request) {
            .path => .path,
            .system => .system,
        };
    }

    /// Returns a slice into this process-lifetime record, or null if unset.
    pub fn source(self: *const SourceRecord) ?LoadSource {
        const text = self.bytes[0..self.len];
        return switch (self.tag) {
            .none => null,
            .path => .{ .path = text },
            .system => .{ .system = text },
        };
    }
};

/// Compares kind and bytes without normalizing paths.
pub fn eqlSource(a: LoadSource, b: LoadSource) bool {
    return switch (a) {
        .path => |pa| switch (b) {
            .path => |pb| std.mem.eql(u8, pa, pb),
            .system => false,
        },
        .system => |sa| switch (b) {
            .system => |sb| std.mem.eql(u8, sa, sb),
            .path => false,
        },
    };
}

fn validateSource(source: LoadSource) LoadError!void {
    const text = switch (source) {
        .path => |p| p,
        .system => |s| s,
    };
    if (text.len == 0) return error.EmptySource;
    if (text.len > max_source_len) return error.SourceTooLong;
    if (std.mem.indexOfScalar(u8, text, 0) != null) return error.InvalidSource;
    switch (source) {
        .path => {
            const absolute = if (builtin.os.tag == .windows)
                switch (std.fs.path.getWin32PathType(u8, text)) {
                    .drive_absolute, .unc_absolute, .local_device, .root_local_device => true,
                    .relative, .rooted, .drive_relative => false,
                }
            else
                std.fs.path.isAbsolutePosix(text);
            if (!absolute) return error.InvalidSource;
        },
        .system => {
            for (text) |byte| {
                if (std.fs.path.isSep(byte)) return error.InvalidSource;
                if (builtin.os.tag == .windows and byte == ':') return error.InvalidSource;
            }
        },
    }
}

/// The table lifecycle state.
pub const Phase = enum(u8) {
    /// Initial state and state after failure; retries are explicit.
    not_loaded = 0,
    /// One thread is filling the table; readers cannot access it.
    loading = 1,
    /// The table is published.
    ready = 2,
};

/// Release/acquire flag that publishes table writes to routed calls.
/// A reader that sees `ready` also sees the initialized table.
pub const Ready = struct {
    phase: std.atomic.Value(u8) = .init(@intFromEnum(Phase.not_loaded)),

    /// Acquire-loads whether the table is published.
    pub fn isReady(self: *const Ready) bool {
        return self.phase.load(.acquire) == @intFromEnum(Phase.ready);
    }

    /// Returns the current phase; loader decisions read it under the lock.
    pub fn state(self: *const Ready) Phase {
        return @enumFromInt(self.phase.load(.acquire));
    }

    /// Stores the table state with release ordering.
    pub fn set(self: *Ready, value: Phase) void {
        self.phase.store(@intFromEnum(value), .release);
    }
};

/// Required export kinds, distinguished by their table representation.
pub const SymbolKind = enum {
    /// Function exports use the translated function-pointer type.
    function,
    /// Object exports are stored by address, never copied.
    data,
};

/// A required export name and its kind.
pub const Symbol = struct {
    /// Exported name from the C header.
    name: [:0]const u8,
    /// Function or object export kind.
    kind: SymbolKind,
};

/// Panics in every optimization mode when a routed call arrives before loading.
/// The message names the library and symbol.
pub fn panicNotReady(library: []const u8, comptime symbol: []const u8) noreturn {
    std.debug.panic(
        "{s}: {s} was called before this module was loaded; call " ++
            "load({{ .path = \"...\" }}) or load({{ .system = \"...\" }}) first",
        .{ library, symbol },
    );
}

/// Whether this target supports dynamic loading; WASI, Emscripten and freestanding targets do not.
pub const supported_target: bool = switch (builtin.os.tag) {
    .wasi, .emscripten, .freestanding => false,
    else => true,
};

/// Config supplies a table, symbols, readiness, assignment and sync hooks, with optional symbols/validation.
/// The loader retains the successful handle and request; failure closes the candidate and publishes nothing.
pub fn Loader(comptime Config: type) type {
    return struct {
        const LoaderType = @This();

        /// The table type filled by this loader.
        pub const table_type = Config.table;

        /// Active or undrained attempt, or null when there is none.
        attempt: ?Attempt = null,

        /// Immutable after READY; read under the lock before publication.
        request: SourceRecord = .{},

        /// Loads and validates a provider, then publishes the table.
        /// Same-source callers share an attempt; failures require explicit retry.
        pub fn load(self: *LoaderType, source: LoadSource) LoadError!void {
            try validateSource(source);
            // Ready fast path: one acquire load, no lock.
            if (Config.ready().isReady()) return self.accept(source);

            Config.sync.lock();
            while (true) {
                switch (Config.ready().state()) {
                    .ready => {
                        Config.sync.unlock();
                        return self.accept(source);
                    },
                    .loading => {
                        const attempt = &self.attempt.?;
                        if (attempt.owner == Config.sync.threadSelf()) {
                            Config.sync.unlock();
                            return error.ReentrantLoad;
                        }
                        if (!eqlSource(self.request.source().?, source)) {
                            Config.sync.unlock();
                            return error.ProviderMismatch;
                        }
                        // Join the active attempt; do not start a competing one.
                        attempt.waiters += 1;
                        while (Config.ready().state() == .loading) Config.sync.wait();
                        const result = attempt.result;
                        attempt.waiters -= 1;
                        // Keep the record until every waiter has taken its result.
                        Config.sync.broadcast();
                        Config.sync.unlock();
                        return result;
                    },
                    .not_loaded => {
                        // Wait for the previous attempt's waiters to drain before retrying.
                        if (self.attempt != null) {
                            Config.sync.wait();
                            continue;
                        }
                        break;
                    },
                }
            }

            self.request.set(source);
            self.attempt = .{ .owner = Config.sync.threadSelf() };
            Config.ready().set(.loading);
            Config.sync.unlock();

            // Run provider constructors without the lock; other callers wait on this attempt.
            const outcome = runAttempt(self.request.source().?);
            const succeeded = if (outcome) |_| true else |_| false;

            Config.sync.lock();
            self.attempt.?.result = outcome;
            Config.ready().set(if (succeeded) .ready else .not_loaded);
            // Wake every waiter; the count is unknown, so broadcast is required.
            Config.sync.broadcast();
            // Keep the result until all attached waiters have taken it.
            while (self.attempt.?.waiters > 0) Config.sync.wait();
            self.attempt = null;
            // Wake callers waiting to start a retry.
            Config.sync.broadcast();
            Config.sync.unlock();

            return outcome;
        }

        /// Returns the retained request, or null before a successful load.
        pub fn loadedSource(self: *const LoaderType) ?LoadSource {
            if (!Config.ready().isReady()) return null;
            return self.request.source();
        }

        fn accept(self: *const LoaderType, source: LoadSource) LoadError!void {
            // An acquire load must have observed readiness before this comparison.
            const published = self.request.source() orelse unreachable;
            if (eqlSource(published, source)) return;
            return error.ProviderMismatch;
        }

        /// Opens, resolves and validates without the loader lock.
        /// Closes the candidate on every failure path.
        fn runAttempt(source: LoadSource) LoadError!void {
            const handle = platform.open(source) catch |err| return err;

            var retain = false;
            defer if (!retain) platform.close(handle);

            if (@hasDecl(Config, "optional_symbols")) {
                inline for (Config.optional_symbols, 0..) |_, index| {
                    Config.assignMissing(index, Config.tablePtr());
                }
            }

            inline for (Config.symbols, 0..) |symbol, index| {
                const address = platform.lookup(handle, symbol.name) orelse
                    return error.MissingSymbol;
                Config.assign(index, Config.tablePtr(), address);
            }

            if (@hasDecl(Config, "optional_symbols")) {
                inline for (Config.optional_symbols, 0..) |symbol, index| {
                    if (platform.lookup(handle, symbol.name)) |address| {
                        Config.assignOptional(index, Config.tablePtr(), address);
                    }
                }
            }

            if (@hasDecl(Config, "validate")) {
                if (Config.validate(Config.tablePtr())) |refusal| {
                    // Include the validation reason in the error report.
                    std.debug.print("{s}: refusing this provider: {s}\n", .{
                        Config.library_name,
                        refusal,
                    });
                    return error.ValidationFailed;
                }
            }

            // The successful table keeps pointers into this handle for process lifetime.
            retain = true;
        }
    };
}

/// One in-flight or undrained load attempt.
const Attempt = struct {
    /// Identity of the thread running the attempt, for the reentrancy check.
    owner: u64,
    /// Published before leaving `loading`; waiters read it only afterward.
    result: LoadError!void = error.OpenFailed,
    /// Waiters remain counted until they take the result.
    waiters: usize = 0,
};

/// Windows path buffer size: 32767 UTF-16 code units plus a terminator.
const windows_path_units = 32768;

const platform = if (builtin.os.tag == .windows)
    Windows
else if (supported_target)
    Unix
else
    NoLoader;

const NoLoader = struct {
    const OpenError = error{ OpenFailed, UnsupportedTarget };

    fn open(source: LoadSource) OpenError!*anyopaque {
        _ = source;
        return error.UnsupportedTarget;
    }
    fn lookup(handle: *anyopaque, name: [:0]const u8) ?*const anyopaque {
        _ = handle;
        _ = name;
        return null;
    }
    fn close(handle: *anyopaque) void {
        _ = handle;
    }
};

const Unix = struct {
    const OpenError = error{ OpenFailed, UnsupportedTarget };

    fn open(source: LoadSource) OpenError!*anyopaque {
        const text = switch (source) {
            .path => |p| p,
            .system => |s| s,
        };
        var buffer: [max_source_len + 1]u8 = undefined;
        @memcpy(buffer[0..text.len], text);
        buffer[text.len] = 0;
        // RTLD_NOW reports missing dependencies at open time.
        // RTLD_LOCAL keeps this provider's symbols out of other SDKs' lookups.
        return std.c.dlopen(
            // `dlopen` requires a sentinel-terminated path.
            buffer[0..text.len :0].ptr,
            .{ .NOW = true, .GLOBAL = false },
        ) orelse error.OpenFailed;
    }

    fn lookup(handle: *anyopaque, name: [:0]const u8) ?*const anyopaque {
        return std.c.dlsym(handle, name.ptr);
    }

    fn close(handle: *anyopaque) void {
        _ = std.c.dlclose(handle);
    }
};

const kernel32 = struct {
    extern "kernel32" fn LoadLibraryExW(
        file_name: [*:0]const u16,
        file: ?*anyopaque,
        flags: u32,
    ) callconv(.winapi) ?*anyopaque;
    extern "kernel32" fn GetProcAddress(module: *anyopaque, name: [*:0]const u8) callconv(.winapi) ?*anyopaque;
    extern "kernel32" fn FreeLibrary(module: *anyopaque) callconv(.winapi) i32;
};

const Windows = struct {
    const OpenError = error{ OpenFailed, UnsupportedTarget, SourceTooLong };

    /// Searches standard directories for names and uses explicit paths as written.
    /// Excludes the current directory.
    const load_library_search_default_dirs: u32 = 0x0000_1000;
    const load_library_search_dll_load_dir: u32 = 0x0000_0100;

    fn open(source: LoadSource) OpenError!*anyopaque {
        const text = switch (source) {
            .path => |p| p,
            .system => |s| s,
        };
        if (text.len > windows_path_units) return error.SourceTooLong;
        var buffer: [windows_path_units + 1]u16 = undefined;
        const units = std.unicode.utf8ToUtf16Le(buffer[0..text.len], text) catch
            return error.OpenFailed;
        buffer[units] = 0;
        return kernel32.LoadLibraryExW(
            buffer[0..units :0],
            null,
            load_library_search_default_dirs | switch (source) {
                .path => load_library_search_dll_load_dir,
                .system => @as(u32, 0),
            },
        ) orelse error.OpenFailed;
    }

    fn lookup(handle: *anyopaque, name: [:0]const u8) ?*const anyopaque {
        return kernel32.GetProcAddress(handle, name.ptr);
    }

    fn close(handle: *anyopaque) void {
        _ = kernel32.FreeLibrary(handle);
    }
};
