# Fork notes

## Source changes

| File | Change |
|---|---|
| `c/` | Carries upstream's C sources, headers, examples and test harness unchanged. |
| `test_vectors/test_vectors.json` | Carries upstream's test vectors unchanged. |
| `LICENSE_A2`, `LICENSE_A2LLVM`, `LICENSE_CC0` | Carry upstream's licence texts unchanged. |
| `README.upstream.md` | Preserves upstream's README unchanged under a new path. |
| `.gitignore` | Adds ignore entries for Zig, consumer, Nix and devenv outputs. |
| `zig/root.zig` | Adds an allocation-free Zig facade over the C hasher and exposes the translated C module. |
| `zig/translate.h` | Includes `<blake3.h>` so TranslateC reads the header for the selected library. |
| `runtime/loader.zig` | Adds explicit provider loading, symbol resolution and synchronized load state for POSIX and Windows. |
| `runtime/sync.h` | Declares the synchronization primitives used by the loader. |
| `runtime/sync.c` | Implements the loader's synchronization primitives. |
| `runtime/generate.zig` | Generates runtime dispatch from the selected TranslateC output. |
| `runtime/graph.zig` | Connects the loader core to the linked and runtime module graphs, sharing loader types between them. |
| `runtime/library.zig` | Defines this library's runtime symbols, ABI requirements, validation and load entry point. |
| `runtime/load_tests.zig` | Adds loader behavior tests using real providers. |
| `runtime/misuse.zig` | Isolates calls made before loading in a child process. |
| `tests.zig` | Exercises the facade against upstream vectors and wrapper-specific cases. |
| `smoke.zig` | Adds the deterministic facade example. |
| `consumer/` | Adds a separate package that depends on this package by path and calls it. |

## Build graph

- `build.zig` compiles upstream C directly; it does not run CMake, Make or a configure script.
- In bundled, linked mode, the public `blake3` module carries the translated declarations and compiled library. Compile-only matrix checks use private modules and target-qualified artifacts, so one target cannot replace another. Each check compiles the library, facade, tests and example.
- The x86 build uses upstream's C intrinsics kernels instead of its assembly kernels. Each kernel is a separate object targeting only its ISA; Zig's resolved target features replace upstream's `-m` flags. The core and dispatcher keep the requested baseline for runtime CPU dispatch.
- AArch64 builds use upstream's NEON kernel. `-Dportable=true` sets upstream's no-SIMD macros and builds the scalar core on any target.
- C translation units use `gnu11` to retain the C11 atomics path. Shared builds add `-fvisibility=hidden`; static builds omit it because visibility does not affect an archive.
- `-Dsystem=true` links the installed library and translates its installed header through `libblake3.pc`; this mode compiles and installs no artifact from the package.
- `-Druntime=true` generates dispatch from the selected translated header and leaves the facade unlinked. Consumers load an explicit provider; there is no path-to-system fallback. Runtime and system modes can combine.
- `-Dlinkage` selects static or shared delivery; static is the default. The build installs the library, public header, pkg-config file and licence records, but not the example.
- The package does not build or ship the upstream Rust crate, `b3sum`, benches, tools or media; those files remain in the repository for upstream provenance.

## Platform boundaries

- `x86` and `x86_64` build SSE2, SSE4.1, AVX2 and AVX-512 (`avx512f` plus `avx512vl`) objects. Runtime dispatch selects a kernel supported by the CPU.
- Little-endian `aarch64` builds NEON. Other architecture tags use the portable core, including big-endian AArch64 and 32-bit ARM, because the upstream NEON source is limited to little-endian AArch64.
- WASI has no dynamic loader; a dynamic-linkage request fails rather than falling back to a static artifact.
- A runtime provider must match the translated header's BLAKE3 ABI configuration, including maximum depth and block, output and key sizes.
