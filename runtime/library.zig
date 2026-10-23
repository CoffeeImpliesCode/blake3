// SPDX-License-Identifier: CC0-1.0 OR Apache-2.0 OR Apache-2.0 WITH LLVM-exception

const rt = @import("rt");

/// Binds the loader to the synchronization symbols emitted by `runtime/sync.c`.
/// Names must use the `blake3_rt` prefix configured in `runtime/graph.zig`.
pub const Sync = struct {
    extern fn blake3_rt_lock() void;
    extern fn blake3_rt_unlock() void;
    extern fn blake3_rt_wait() void;
    extern fn blake3_rt_broadcast() void;
    // Matches C's 64-bit `unsigned long long` in supported ABIs.
    extern fn blake3_rt_thread_self() u64;

    pub fn lock() void {
        blake3_rt_lock();
    }
    pub fn unlock() void {
        blake3_rt_unlock();
    }
    pub fn wait() void {
        blake3_rt_wait();
    }
    pub fn broadcast() void {
        blake3_rt_broadcast();
    }
    pub fn threadSelf() u64 {
        return blake3_rt_thread_self();
    }
};

/// Builds the loader configuration for the generated dispatch type.
pub fn Config(comptime dispatch: type) type {
    return struct {
        /// Used in the pre-load panic.
        pub const library_name = "blake3";

        /// Dispatch table and generated symbol lists.
        pub const table = dispatch.Table;
        pub const symbols = dispatch.symbols;
        pub const optional_symbols = dispatch.optional_symbols;

        /// Namespaced binding for this SDK's synchronization functions.
        pub const sync = Sync;

        pub fn tablePtr() *table {
            return dispatch.tablePtr();
        }

        pub fn ready() *rt.Ready {
            return &dispatch.ready;
        }

        pub fn assign(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assign(index, dst, address);
        }

        pub inline fn assignOptional(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assignOptional(index, dst, address);
        }

        pub inline fn assignMissing(comptime index: usize, dst: *table) void {
            dispatch.assignMissing(index, dst);
        }

        /// Runs the library-specific check after symbol resolution and before publication.
        pub fn validate(dst: *const table) ?[]const u8 {
            const version = dst.blake3_version();
            if (version == null or version[0] == 0) {
                return "blake3_version() returned null or an empty string";
            }
            return null;
        }
    };
}
