//! Zig facade over BLAKE3's canonical C implementation.
//!
//! No part of the algorithm is reimplemented here. Every byte this module
//! returns is produced by the C under `c/`, reached through `pub const c`,
//! the module `b.addTranslateC` produces from `blake3.h`. What the facade
//! adds is the part a C header cannot express: a length checked by the
//! compiler instead of by a comment, a caller-owned output slice instead of a
//! bare pointer, and one documented decision about how a context string
//! reaches the key derivation.
//!
//! ## Import routes
//!
//! One Zig route is published: `dep.module("blake3")` in the dependent's
//! `build.zig`, which is `@import("blake3")` in source. The raw translated
//! header is `c` on that same module and is not published as a module of its
//! own, so the declarations and the library that satisfies them arrive
//! through one route. A C consumer takes the installed header and archive
//! instead; `README.zig.md` names that layout and what system mode does not
//! install.
//!
//! The shortest sequence that uses this module:
//!
//! ```zig
//! const std = @import("std");
//! const blake3 = @import("blake3");
//!
//! pub fn main() void {
//!     var digest: blake3.Out = undefined;
//!     blake3.hash("hello", &digest);
//!     std.debug.print("{s}\n", .{std.fmt.bytesToHex(digest, .lower)});
//! }
//! ```
//!
//! Split input across `init`, `update` and `finalize` instead. `initKeyed` and
//! `initDeriveKey` are the other two modes, and `hashKeyed` and `deriveKey`
//! are their one-shot forms. This package is developed and gated against Zig
//! 0.16.0, which is the floor `build.zig.zon` records.
//!
//! ## What this module does not do
//!
//! It allocates nothing and owns nothing, and it does not wrap the hasher in
//! a type that hides upstream's fields: `Hasher` is `c.blake3_hasher`, so
//! every field is reachable and writing one leaves the caller with its own
//! state contract. No TBB entry point is declared, because this build has
//! none: `blake3_hasher_update_tbb` sits behind `BLAKE3_USE_TBB`
//! (`c/blake3.h:72-75`), which neither mode defines, so it is not in `c`
//! either.
//!
//! ## Two configurations: linked and runtime-loaded
//!
//! This module is built in one of two shapes, and `runtime_loaded` says which
//! at comptime.
//!
//! *Linked* is the default. The C library is linked, `c` is the translated
//! header, and every call below is a direct call with no table and no check.
//!
//! *Runtime-loaded* is opt-in. The library is not linked; `c` is a dispatch
//! generated from the same translation step's output, and the nine entry
//! points `c/blake3.h:63-80` declares are resolved through the platform loader
//! when the caller calls
//!
//! ```zig
//! try blake3.load(.{ .path = "/usr/lib/libblake3.so.0" });
//! ```
//!
//! before using anything else. A call into a module that has not loaded stops
//! the program with a message naming the function, in every optimization mode.
//! That is a programming error rather than a recoverable condition: the table
//! does not exist yet, and there is no partial state to fall back on. The load
//! itself reports a missing file, a provider that does not export what the
//! header declares, a request that cannot be honoured because a different
//! provider already won, or a reentrant call, as errors rather than as a
//! different library being loaded instead.
//!
//! The provider is reached, never guessed. `.path` names a file and `.system`
//! names a library for the platform loader; neither falls back to the other,
//! the module has no unload and no reset, and it keeps the handle and its own
//! copy of the request to the end of the process.
//!
//! What a provider must be is stated in `runtime/library.zig`, next to the ABI
//! boundary and what is and is not checked about it.
//!
//! ## Allocation
//!
//! There is none, and this module never grows an allocator. `Hasher` is
//! `blake3_hasher` itself, whose size is dominated by the
//! `(BLAKE3_MAX_DEPTH + 1) * BLAKE3_OUT_LEN` byte chaining-value stack that
//! upstream reserves for lazy merging (`c/blake3.h:51-61`), and it is returned
//! by value or borrowed through a pointer. Upstream allocates nothing, so
//! there is nothing here for a caller to free: buffers in, bytes out, and the
//! caller owns every one of them. There is no `deinit`, because there is
//! nothing to release.
//!
//! ## Errors
//!
//! This module returns no errors, and that is upstream's shape rather than an
//! omission. Every `blake3_hasher_*` entry point in `c/blake3.h:64-80` is
//! `void` and none of them can fail: there is no allocation to fail, no
//! length to reject, and no NULL to translate. The one declaration in that
//! block that returns anything is `blake3_version` at `c/blake3.h:63`, a
//! NUL-terminated string naming the library that got linked. Inventing an
//! error union would mean reporting conditions that cannot occur, so the
//! three ways a caller could get a call wrong are closed elsewhere instead:
//!
//!   * The key is a `Key`, an array of exactly `key_len` bytes, so a 16- or
//!     64-byte key does not compile.
//!   * The output is a slice, and the call writes exactly `out.len` bytes of
//!     it and nothing outside. A caller that wants 32 bytes gets 32 bytes;
//!     one that wants 131 gets the whole extended output.
//!   * The derive-key context is passed by length, so a context string that
//!     happens to contain a NUL byte is still hashed in full. See
//!     `initDeriveKey`.
//!
//! ## Threading
//!
//! A `Hasher` is plain mutable state with no locking, so it belongs to one
//! thread at a time. Nothing else in this module is shared, because nothing
//! else is stateful: `init*` builds a fresh value, and the arithmetic is
//! upstream's.

/// The translated `blake3.h`, i.e. upstream's ABI exactly as published.
///
/// This is the escape hatch for a caller that needs a declaration the facade
/// does not name (`blake3_version`, or `blake3_hasher_init_derive_key`, the
/// C-string entry point this facade deliberately does not use) and for the
/// struct fields themselves. It is the same module the facade calls, on the
/// same library, so importing the facade is all a dependent needs to reach it;
/// it is not published under a name of its own.
///
/// The declarations are for whichever header this build selected: bundled
/// mode translates `c/blake3.h`, system mode the installed one. A caller
/// that reaches past the facade gets upstream behaviour and inherits every
/// obligation upstream declares, including the rule that a `blake3_hasher` is
/// only valid in a state reached for it; the facade states that rule for
/// `Hasher` over the states its own functions produce.
///
/// In a runtime-loading build this module is a generated dispatch instead of
/// the translation step's own output. It publishes the same namespace: every
/// type and constant is re-exported from the translated header rather than
/// restated, so `Hasher` is the same nominal type either way and nothing here
/// needs a cast. What differs is how a name reaches the library. In the linked
/// configuration it is a direct call; in the runtime-loaded one it is a call
/// through a table that `load` fills, and a call before that fill stops the
/// program with a message naming the function. `runtime_loaded` says which
/// configuration this build is, at comptime.
pub const c = @import("c");
const std = @import("std");

/// The loader core, which is where a linked build's two public types come from.
///
/// It is imported only by the linked configuration. In a runtime-loading build
/// the dispatch carries its own copy of the same declarations, and this module
/// is never referenced, so it is never resolved and never compiled. Either way
/// there is exactly one `LoadSource` and one `LoadError` in a build, which is
/// what keeps them one type for a consumer that names them.
const rt = @import("rt");

/// Whether this module was configured to resolve its native symbols at run
/// time.
///
/// False for the ordinary build, where the C library is linked and `c` is the
/// translated header itself. True when the build generated a dispatch that
/// resolves the same symbols through the platform loader, in which case `load`
/// is the call that makes the library usable.
///
/// It is a comptime constant, so a consumer can write two different code paths
/// and have only the one it chose analyzed.
pub const runtime_loaded: bool = if (@hasDecl(c, "rt_runtime_loaded")) c.rt_runtime_loaded else false;

/// Which native library `load` should open.
///
/// `.path` is an explicit file path and `.system` is an explicit name for the
/// platform loader. There is no path-to-system fallback and no implicit
/// fallback of any kind; a request that cannot be honoured is an error, not a
/// different library.
pub const LoadSource = if (runtime_loaded) c.LoadSource else rt.LoadSource;

/// Every way `load` can decline.
///
/// Declared here, in the module a consumer imports, rather than only inside the
/// loader: the caller names the failure it is handling.
pub const LoadError = if (runtime_loaded) c.LoadError else rt.LoadError;

/// Load the native library this module dispatches to.
///
/// In a runtime-loading build this is the whole contract: call it once, then
/// use this module as if it were linked. Calling it again with the same request
/// succeeds and changes nothing; calling it with a different request after a
/// success is `ProviderMismatch`, and the library already in use stays in use.
/// A failed attempt publishes nothing and can be retried explicitly, by
/// calling this again: there is no automatic retry, and no implicit second
/// source.
///
/// It keeps the process handle and its own copy of the request to the end of
/// the process. There is no unload and no reset, because the table is
/// process-global state that other code may already have called through.
///
/// Safe to call from any thread. A thread that arrives while an attempt for the
/// same request is in flight waits for that attempt and gets its result,
/// whatever it was. A call from the thread that is running the attempt is
/// `ReentrantLoad` rather than a deadlock.
///
/// In a linked build there is no provider, no table and nothing to resolve, so
/// this stops the program with a message saying so instead of quietly
/// succeeding. `runtime_loaded` is false there, so a consumer that supports
/// both configurations can tell the two apart at comptime instead of meeting
/// this at run time.
pub fn load(source: LoadSource) LoadError!void {
    if (comptime !runtime_loaded) {
        std.debug.panic(
            "blake3: load was called on a linked build; this module is not " ++
                "runtime-loaded, so there is no library to load. Build with " ++
                "runtime loading configured, or do not call load.",
            .{},
        );
    }
    return c.load(source);
}

/// The request that succeeded, or null when nothing has loaded yet.
///
/// The answer is the loader's own retained copy and stays valid for the life of
/// the process. Null in a linked build, which has no request.
pub fn loadedSource() ?LoadSource {
    if (comptime !runtime_loaded) return null;
    return c.loadedSource();
}

/// Default output length in bytes, `BLAKE3_OUT_LEN` (`c/blake3.h:35`).
pub const out_len: usize = c.BLAKE3_OUT_LEN;

/// Keyed-mode key length in bytes, `BLAKE3_KEY_LEN` (`c/blake3.h:34`).
pub const key_len: usize = c.BLAKE3_KEY_LEN;

/// The compression function's block size in bytes, `BLAKE3_BLOCK_LEN`
/// (`c/blake3.h:36`). A chunk is 16 whole blocks, and an input that ends
/// mid-block is padded with zeros to the end of its last block.
pub const block_len: usize = c.BLAKE3_BLOCK_LEN;

/// The tree's leaf size in bytes, `BLAKE3_CHUNK_LEN` (`c/blake3.h:37`).
/// Anything longer than this becomes a tree, which is why a `Hasher` holds a
/// chaining-value stack at all.
pub const chunk_len: usize = c.BLAKE3_CHUNK_LEN;

/// The key a keyed-mode hasher is initialised with.
pub const Key = [key_len]u8;

/// A default-length digest. Longer outputs are requested by passing a longer
/// slice to `finalize`.
pub const Out = [out_len]u8;

/// Upstream's hasher state, unchanged.
///
/// This is `blake3_hasher` and nothing else, so a value produced here can be
/// handed to `c` directly and vice versa. Treat it as opaque: upstream
/// documents the struct as a private implementation detail that is public only
/// because it has to appear in the struct definition (`c/blake3.h:40-41`).
///
/// A value is valid in the states `init`, `initKeyed` and `initDeriveKey`
/// return and the states `update` and `reset` derive from them. Zeroed,
/// `undefined` or otherwise hand-built storage is not a valid hasher, and
/// upstream carries no flag that could tell the two apart; a `Hasher` is a
/// constructed value, not an arbitrary block of bytes. Nothing in the type
/// prevents a caller from writing those fields: in Zig they are all reachable.
/// A caller that does is holding its own state, and none of what follows
/// applies to it.
///
/// It owns nothing: the struct is plain data and upstream allocates nothing,
/// so there is no `deinit` to call and nothing to release. A copy is a copy
/// of that data and is an independent hasher: updating or resetting one
/// leaves the other exactly as it was, and either may be finalized on its
/// own. No stable address is required, so a `Hasher` may be returned by
/// value, stored inside another struct or moved freely. The only state
/// upstream shares between threads is its CPU-feature cache, which it
/// guards with atomics (`c/blake3_dispatch.c:105-108`), so a copy handed
/// to another thread is as independent there as it is here.
pub const Hasher = c.blake3_hasher;

/// A hasher in the ordinary unkeyed hashing mode.
///
/// Upstream passes a clear flags word here (`c/blake3.c:390`,
/// `hasher_init_base(self, IV, 0)`), and that empty flags word is what selects
/// this mode rather than keyed or derive-key.
pub fn init() Hasher {
    var self: Hasher = undefined;
    c.blake3_hasher_init(&self);
    return self;
}

/// A hasher in keyed mode, which makes it a PRF and a MAC.
///
/// The key must be exactly `key_len` bytes; the type carries that length, so
/// there is nothing to check at run time and no way to call this with a short
/// or long key. A key is a secret, not a password: this is a fast MAC, and
/// upstream's own warning about password hashing applies (`README.md:80-83`:
/// "BLAKE3 is not a password hashing algorithm").
///
/// The key is copied into the hasher (`c/blake3.c:385`), so a caller may wipe
/// or reuse its own copy as soon as this returns.
pub fn initKeyed(key: Key) Hasher {
    var self: Hasher = undefined;
    // Upstream takes the key as `const uint8_t key[BLAKE3_KEY_LEN]`, which
    // translate-c may render either as a 32-element array value or as the
    // pointer a C array parameter decays to. A `*const [key_len]u8` coerces
    // to both, so the call compiles either way without a cast.
    const key_ref: *const [key_len]u8 = &key;
    c.blake3_hasher_init_keyed(&self, key_ref);
    return self;
}

/// A hasher in key-derivation mode, for a context string and key material.
///
/// `context` is hashed with its length, through upstream's
/// `blake3_hasher_init_derive_key_raw` (`c/blake3.h:68-69`), not through
/// `blake3_hasher_init_derive_key`, which is `strlen(context)` and the same
/// call (`c/blake3.c:411-413`). That choice is deliberate and observable: a
/// context containing a NUL byte is a different context here, where the C
/// string entry point would silently truncate it and derive the same key as
/// the prefix. Contexts are meant to be short, hardcoded, globally unique
/// strings (`README.md:158-160`), so nothing legitimate contains a NUL, and
/// the length-taking form is the one that cannot surprise.
///
/// The material goes in through `update` afterwards; an empty context is
/// accepted and hashed as zero bytes.
///
/// `context` is read during the call and is not retained: upstream hashes it
/// through a temporary hasher and keeps only the key it derives
/// (`c/blake3.c:399-409`), so the caller may free or overwrite the slice as
/// soon as this returns.
pub fn initDeriveKey(context: []const u8) Hasher {
    var self: Hasher = undefined;
    // `const void *` is a `?*const anyopaque` in the translated header. The
    // cast is the child type widening from `u8` to `anyopaque` and nothing
    // else: the pointer, the constness and the alignment are unchanged.
    const context_ptr: *const anyopaque = @ptrCast(context.ptr);
    c.blake3_hasher_init_derive_key_raw(&self, context_ptr, context.len);
    return self;
}

/// Absorb more input. The split points do not matter.
///
/// Upstream buffers into a block and compresses whole chunks (`c/blake3.c`,
/// `blake3_hasher_update_base`), so a caller may hand over one byte at a time,
/// whole chunks, or anything in between and get the same digest. An empty
/// slice is accepted and writes nothing. This does not touch `self`'s mode.
///
/// `input` is borrowed for the duration of the call and is not retained:
/// upstream copies whatever it has not compressed yet into the hasher's own
/// buffer (`c/blake3.c:35-45`), so the caller may overwrite or free it as soon
/// as this returns. That copy is a `memcpy`, so `input` must not overlap the
/// hasher's own storage: every `Hasher` field is reachable, and handing
/// `update` a slice of the hasher it writes to is an overlapping copy.
pub fn update(self: *Hasher, input: []const u8) void {
    // Same widening as `initDeriveKey`: `const void *input`.
    const input_ptr: *const anyopaque = @ptrCast(input.ptr);
    c.blake3_hasher_update(self, input_ptr, input.len);
}

/// Write `out.len` bytes of output and leave the hasher unchanged.
///
/// `out.len` is the output length the caller asked for, and it is what
/// distinguishes a digest from the extendable output: 32 bytes is the
/// conventional digest, more is the same hash function read further along its
/// output stream (`c/blake3.c`, `output_root_bytes`). A zero-length `out`
/// writes nothing, which upstream checks for explicitly before touching the
/// pointer (`c/blake3.c:604-612`).
///
/// `self` is taken as `const` because upstream finalizes through
/// `const blake3_hasher *` (`c/blake3.h:76-77`): finalizing does not disturb
/// the state, so a caller may finalize the same hasher as often as it likes,
/// at as many lengths as it likes.
///
/// `out` is the caller's buffer and is written in full: `out.len` bytes, and
/// nothing outside them. The hasher keeps no reference to it afterwards, so
/// the caller may reuse the buffer at once. It must not overlap the hasher's
/// own storage: upstream finishes reading the state it needs before it writes
/// the first output byte, so an overlap happens to be harmless in this
/// implementation and is not a supported input.
pub fn finalize(self: *const Hasher, out: []u8) void {
    c.blake3_hasher_finalize(self, out.ptr, out.len);
}

/// Write `out.len` bytes of output starting `seek` bytes into the output
/// stream.
///
/// This is how the same hasher yields a window into its output without
/// hashing the prefix again: `seek` is a byte offset counted from the start of
/// the extendable output, and `seek + out.len` may run past 32 bytes. It is
/// the same function `finalize` calls with `seek = 0` (`c/blake3.c:599-602`),
/// so any window reachable here is also the matching window of one long
/// `finalize`.
///
/// The buffer duties are `finalize`'s: `out` is the caller's, is written in
/// full, and must not overlap the hasher's own storage.
pub fn finalizeSeek(self: *const Hasher, seek: u64, out: []u8) void {
    c.blake3_hasher_finalize_seek(self, seek, out.ptr, out.len);
}

/// Return the hasher to the state it had when it was initialised.
///
/// The mode is kept, not cleared: `blake3_hasher_reset` re-seeds the chunk
/// from `self->key` and clears the counter and the chaining-value stack
/// (`c/blake3.c:648-651`), and the key and the flags that select keyed or
/// derive-key mode are untouched. So a keyed hasher reset and reused still
/// authenticates with the same key, and a derive-key hasher reset and reused
/// still derives from the same context. That is what makes a hasher reusable
/// across unrelated inputs instead of single-use.
pub fn reset(self: *Hasher) void {
    c.blake3_hasher_reset(self);
}

/// The unkeyed digest of `input`, written to `out`.
///
/// Equivalent to `init`, `update`, `finalize`, and the one-shot form for the
/// caller who has the whole input already and needs no state between calls.
///
/// Both buffers are the caller's and neither is retained; the buffer duties
/// are `update`'s and `finalize`'s.
pub fn hash(input: []const u8, out: []u8) void {
    var hasher = init();
    update(&hasher, input);
    finalize(&hasher, out);
}

/// The keyed digest of `input` under `key`, written to `out`.
///
/// Equivalent to `initKeyed`, `update`, `finalize`.
/// The buffer duties are `update`'s and `finalize`'s.
pub fn hashKeyed(key: Key, input: []const u8, out: []u8) void {
    var hasher = initKeyed(key);
    update(&hasher, input);
    finalize(&hasher, out);
}

/// A key derived from `context` and `key_material`, written to `out`.
///
/// In this mode `key_material` is not a password and never should be: it is
/// key material, and `context` is the domain separator that keeps two uses of
/// the same material from producing the same key (`README.md`).
/// Equivalent to `initDeriveKey`, `update`, `finalize`.
/// Both inputs are read during the call and neither is retained; the buffer
/// duties are `update`'s and `finalize`'s.
pub fn deriveKey(context: []const u8, key_material: []const u8, out: []u8) void {
    var hasher = initDeriveKey(context);
    update(&hasher, key_material);
    finalize(&hasher, out);
}
