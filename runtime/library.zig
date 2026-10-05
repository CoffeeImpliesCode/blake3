// SPDX-License-Identifier: CC0-1.0 OR Apache-2.0 OR Apache-2.0 WITH LLVM-exception
//
//! BLAKE3's side of the runtime loader: the names its synchronization binding
//! has, and what it requires of a provider beyond resolving its symbols.
//!
//! Everything else about the runtime route is generic. `runtime/loader.zig` is
//! the state machine and the platform layer; `runtime/generate.zig` builds the
//! dispatch from whatever the translation step actually produced; `runtime/graph.zig`
//! wires them together. This file is what makes them BLAKE3's, and it is the
//! file another SDK replaces.
//!
//! ## What a provider must be
//!
//! The nine entry points of `c/blake3.h:63-80`, all of them: `blake3_version`,
//! `blake3_hasher_init`, `blake3_hasher_init_keyed`,
//! `blake3_hasher_init_derive_key`, `blake3_hasher_init_derive_key_raw`,
//! `blake3_hasher_update`, `blake3_hasher_finalize`,
//! `blake3_hasher_finalize_seek` and `blake3_hasher_reset`.
//! `blake3_hasher_update_tbb` is deliberately not among them: it exists only
//! under `BLAKE3_USE_TBB` (`c/blake3.h:72-75`), which neither mode of this build
//! defines, so it is not in the translated header and not in the table.
//!
//! ## The ABI boundary, stated honestly
//!
//! The provider is compiled from a header with the same `BLAKE3_MAX_DEPTH`,
//! `BLAKE3_BLOCK_LEN`, `BLAKE3_OUT_LEN` and `BLAKE3_KEY_LEN` this build's
//! translated header used, because those macros fix `blake3_hasher`'s layout
//! (`c/blake3.h:40-61`) and the sizes the facade's own types are built from.
//! The C ABI, the platform's scalar widths and that struct layout are the
//! requirements; which SIMD kernel the provider was compiled with is not one,
//! because every kernel produces the same digest through the same entry points.
//!
//! Resolving the symbols and translating the header are the boundary. They are
//! not proof that a provider is compatible, and this file does not pretend to
//! add one: the only thing checked at load time is that `blake3_version()`
//! answers with a non-empty NUL-terminated string, which is a check that the
//! entry point behaves, not a compatibility verdict.

const rt = @import("rt");

/// The synchronization this loader calls, bound by exact name.
///
/// The names below are `runtime/sync.h` compiled with
/// `RT_SYNC_PREFIX=blake3_rt`, which is what `runtime/graph.zig` passes. Two
/// spellings of that prefix have to agree: this file names the symbols, and
/// graph.zig defines the macro. A build where they disagree does not link, and
/// that is the whole error report: there is no runtime path that could hide it.
///
/// The core in `runtime/loader.zig` never names a symbol of its own, which is
/// what lets two SDKs, or two configurations of one SDK, hold their own loader
/// state in one process without sharing any of it.
pub const Sync = struct {
    extern fn blake3_rt_lock() void;
    extern fn blake3_rt_unlock() void;
    extern fn blake3_rt_wait() void;
    extern fn blake3_rt_broadcast() void;
    // `unsigned long long`. Declared as u64, which is the same type in every
    // ABI this SDK targets: 64-bit on x86_64, aarch64, riscv64 and wasm32.
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

/// The loader's configuration for this SDK, given the dispatch that owns the
/// table.
///
/// `dispatch` is the generated module, passed as a type by the dispatch itself
/// so that this file never has to import it. The direction is one-way on
/// purpose: the descriptor knows what the loader needs, the dispatch knows what
/// the header said, and neither imports the other.
pub fn Config(comptime dispatch: type) type {
    return struct {
        /// Named in the pre-load panic, so the message says which library was
        /// reached for before it was loaded.
        pub const library_name = "blake3";

        /// The table the generated dispatch declares, and the symbols it needs
        /// to fill it. Both come from the translated header, not from this file.
        pub const table = dispatch.Table;
        pub const symbols = dispatch.symbols;
        pub const optional_symbols = dispatch.optional_symbols;

        /// The project's namespaced synchronization binding.
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

        /// The one library-specific check, run after every symbol resolved and
        /// before anything is published.
        pub fn validate(dst: *const table) ?[]const u8 {
            const version = dst.blake3_version();
            if (version == null or version[0] == 0) {
                return "blake3_version() returned null or an empty string";
            }
            return null;
        }
    };
}