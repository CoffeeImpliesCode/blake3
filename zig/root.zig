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
//! ## Allocation
//!
//! There is none, and this module never grows an allocator. `Hasher` is
//! `blake3_hasher` itself, whose size is dominated by the
//! `(BLAKE3_MAX_DEPTH + 1) * BLAKE3_OUT_LEN` byte chaining-value stack that
//! upstream reserves for lazy merging (`c/blake3.h:51-61`), and it is returned
//! by value or borrowed through a pointer. Upstream allocates nothing, so
//! there is nothing here for a caller to free: buffers in, bytes out, and the
//! caller owns every one of them.
//!
//! ## Errors
//!
//! This module returns no errors, and that is upstream's shape rather than an
//! omission. Every hasher entry point in `c/blake3.h:63-80` is `void` and
//! none of them can fail: there is no allocation to fail, no length to
//! reject, and no NULL to translate. Inventing an error union would mean
//! reporting conditions that cannot occur, so the three ways a caller could
//! get a call wrong are closed elsewhere instead:
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
/// This is the escape hatch for the caller that needs something the facade
/// does not name: `blake3_hasher_update_tbb`, a symbol this header declares
/// only when the library is built with TBB, or the struct fields themselves.
/// A caller that goes through it gets upstream behaviour with none of the
/// guarantees above, which is the point of it being public.
pub const c = @import("c");

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
/// upstream's own warning about password hashing applies (`README.md`, "BLAKE3
/// is not a password hashing algorithm").
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
/// strings (`README.md`), so nothing legitimate contains a NUL, and the
/// length-taking form is the one that cannot surprise.
///
/// The material goes in through `update` afterwards; an empty context is
/// accepted and hashed as zero bytes.
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
pub fn hash(input: []const u8, out: []u8) void {
    var hasher = init();
    update(&hasher, input);
    finalize(&hasher, out);
}

/// The keyed digest of `input` under `key`, written to `out`.
///
/// Equivalent to `initKeyed`, `update`, `finalize`.
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
pub fn deriveKey(context: []const u8, key_material: []const u8, out: []u8) void {
    var hasher = initDeriveKey(context);
    update(&hasher, key_material);
    finalize(&hasher, out);
}
