//! Zig facade over BLAKE3's canonical C implementation; hashing calls allocate no memory.
//!
/// The upstream `blake3.h` namespace for declarations not named by this facade.
/// Linked builds translate the header; runtime-loaded builds expose a dispatch with the same types.
pub const c = @import("c");
const std = @import("std");

// Linked-build source of `LoadSource` and `LoadError`.
const rt = @import("rt");

/// True when symbols resolve at run time; call `load` before using the facade.
pub const runtime_loaded: bool = if (@hasDecl(c, "rt_runtime_loaded")) c.rt_runtime_loaded else false;

/// Selects an explicit file path or platform loader name; there is no fallback.
pub const LoadSource = if (runtime_loaded) c.LoadSource else rt.LoadSource;

/// Errors returned by a runtime-loaded `load` request.
pub const LoadError = if (runtime_loaded) c.LoadError else rt.LoadError;

/// Loads and retains the library until process exit; linked builds panic. Runtime failures return `LoadError`; retry is explicit.
/// Identical requests succeed or await an in-flight result; different requests after success return `ProviderMismatch`, reentry `ReentrantLoad`.
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

/// Returns the retained request, or null when no library has loaded or in linked builds.
/// The returned request remains valid until process exit.
pub fn loadedSource() ?LoadSource {
    if (comptime !runtime_loaded) return null;
    return c.loadedSource();
}

/// Default digest length in bytes.
pub const out_len: usize = c.BLAKE3_OUT_LEN;

/// Key length in bytes.
pub const key_len: usize = c.BLAKE3_KEY_LEN;

/// Compression block size in bytes.
pub const block_len: usize = c.BLAKE3_BLOCK_LEN;

/// BLAKE3 chunk size in bytes.
pub const chunk_len: usize = c.BLAKE3_CHUNK_LEN;

/// Fixed-size key for keyed mode.
pub const Key = [key_len]u8;

/// Default-length digest; pass a larger slice to `finalize` for extended output.
pub const Out = [out_len]u8;

/// Upstream `blake3_hasher` state; initialize it with `init*` before use.
/// Caller-owned state; copies are independent. Use each hasher on one thread at a time; no `deinit` is needed.
pub const Hasher = c.blake3_hasher;

/// Returns a new unkeyed hasher.
pub fn init() Hasher {
    var self: Hasher = undefined;
    c.blake3_hasher_init(&self);
    return self;
}

/// Returns keyed-mode state for PRF/MAC use and copies `key` into it.
/// Use secret key material, not passwords.
pub fn initKeyed(key: Key) Hasher {
    var self: Hasher = undefined;
    // Translate-C may render the C array parameter as an array or pointer;
    // this pointer-to-array coerces to both forms.
    const key_ref: *const [key_len]u8 = &key;
    c.blake3_hasher_init_keyed(&self, key_ref);
    return self;
}

/// Returns derive-key state for `context`, hashing its full length, including NUL bytes.
/// Borrows but does not retain `context`.
pub fn initDeriveKey(context: []const u8) Hasher {
    var self: Hasher = undefined;
    // Widen the byte pointer for C's `const void *` parameter.
    const context_ptr: *const anyopaque = @ptrCast(context.ptr);
    c.blake3_hasher_init_derive_key_raw(&self, context_ptr, context.len);
    return self;
}

/// Absorbs `input` without retaining it; it must not overlap `self`.
pub fn update(self: *Hasher, input: []const u8) void {
    const input_ptr: *const anyopaque = @ptrCast(input.ptr);
    c.blake3_hasher_update(self, input_ptr, input.len);
}

/// Writes `out.len` bytes without changing `self`; zero-length output writes nothing.
/// The caller owns `out`, which must not overlap `self`.
pub fn finalize(self: *const Hasher, out: []u8) void {
    c.blake3_hasher_finalize(self, out.ptr, out.len);
}

/// Writes `out.len` bytes from output offset `seek`; `self` is unchanged.
/// The caller owns `out`, which must not overlap `self`.
pub fn finalizeSeek(self: *const Hasher, seek: u64, out: []u8) void {
    c.blake3_hasher_finalize_seek(self, seek, out.ptr, out.len);
}

/// Restores the initial message state while preserving the hasher's mode and key.
pub fn reset(self: *Hasher) void {
    c.blake3_hasher_reset(self);
}

/// Writes the unkeyed hash of `input` to caller-owned `out`; retains neither slice.
pub fn hash(input: []const u8, out: []u8) void {
    var hasher = init();
    update(&hasher, input);
    finalize(&hasher, out);
}

/// Writes the keyed hash to caller-owned `out`; `input` and `out` are not retained.
pub fn hashKeyed(key: Key, input: []const u8, out: []u8) void {
    var hasher = initKeyed(key);
    update(&hasher, input);
    finalize(&hasher, out);
}

/// Derives a key from `key_material` under the `context` domain separator, into `out`.
/// Inputs and output are not retained; use key material, not passwords.
pub fn deriveKey(context: []const u8, key_material: []const u8, out: []u8) void {
    var hasher = initDeriveKey(context);
    update(&hasher, key_material);
    finalize(&hasher, out);
}
