# Zig facade API

## Types and constants

The facade exports `out_len` (32), `key_len` (32), `block_len` (64), and `chunk_len` (1024). `Out` is the 32-byte default output, `Key` is a 32-byte key, and `Hasher` is upstream's `blake3_hasher` type. `c` exposes the translated C header.

## Hash operations

| Operation | Behavior |
|---|---|
| `init()` | Create an unkeyed hasher |
| `initKeyed(key)` | Create a keyed hasher for PRF or MAC use |
| `initDeriveKey(context)` | Create a key-derivation hasher |
| `update(&hasher, input)` | Absorb input; input may arrive in any number of chunks |
| `finalize(&hasher, out)` | Write `out.len` bytes from the current output stream |
| `finalizeSeek(&hasher, seek, out)` | Write `out.len` bytes from the stream at byte `seek` |
| `reset(&hasher)` | Restore the initial state and keep its mode |
| `hash`, `hashKeyed`, `deriveKey` | One-shot forms of the unkeyed, keyed, and derivation modes |

## Contracts

- Initialize `Hasher` with `init`, `initKeyed`, or `initDeriveKey`. A zeroed, `undefined`, or manually constructed value is invalid. Do not modify its fields directly.
- A copied hasher is independent. A mutable hasher is not thread-safe; use each instance from one thread at a time.
- The facade allocates no memory and has no deinitializer. The caller owns all input and output buffers.
- `update` borrows its input for the call and does not retain it. Do not overlap input or output buffers with hasher storage.
- `finalize` and `finalizeSeek` leave the hasher unchanged and retain no output pointer. A zero-length output writes nothing. An empty update is a no-op.
- `initKeyed` takes a fixed-size key. `initDeriveKey` treats its context as a byte slice, so an embedded NUL is part of the context.
- Hash operations have no error return.

## Runtime-loaded API

Build with `-Druntime=true` to use the runtime loader. In this mode the facade does not link a native library into its module. `runtime_loaded` is true. In a linked build it is false, and calling `load` panics.

| Name | Type or behavior |
|---|---|
| `LoadSource` | `union(enum) { path: []const u8, system: []const u8 }` |
| `load(source)` | `LoadError!void`; load from an explicit absolute path or pass a system-library basename unchanged |
| `loadedSource()` | `?LoadSource`; null until a provider loads successfully |
| `LoadError` | `error{EmptySource, OpenFailed, MissingSymbol, ProviderMismatch, ReentrantLoad}` |

A path is never retried as a system name. A system name is not searched in a directory. A failed load does not fall back to a linked library. There is no public unload; source bytes are used only during the call.

| Error | Meaning |
|---|---|
| `EmptySource` | The source name is empty |
| `OpenFailed` | The platform loader cannot open the provider |
| `MissingSymbol` | The provider does not export a required symbol |
| `ProviderMismatch` | A different source is requested after a provider loads |
| `ReentrantLoad` | A thread calls `load` while it is already in a load attempt |

The provider must be a dynamically loadable BLAKE3 C library built with the same header and configuration. It must export these nine symbols:

```text
blake3_version
blake3_hasher_init
blake3_hasher_init_keyed
blake3_hasher_init_derive_key
blake3_hasher_init_derive_key_raw
blake3_hasher_update
blake3_hasher_finalize
blake3_hasher_finalize_seek
blake3_hasher_reset
```

The loader checks that `blake3_version()` returns a non-null, non-empty, NUL-terminated string. This check does not prove ABI compatibility. A static musl or `-static` binary has no `dlopen` and cannot use this route. Use one instance of this SDK's runtime state per binary because the synchronization symbols use the `blake3_rt` prefix.
