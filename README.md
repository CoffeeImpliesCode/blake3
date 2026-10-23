# BLAKE3 for Zig

This package wraps upstream BLAKE3 1.8.7 and builds its C library.
It provides an allocation-free Zig facade for the C API.

## Source deviations

No upstream C source, header, assembly, example, test vector, or licence text is modified. The only upstream file changed is `.gitignore`, with appended ignore entries. The fork adds a Zig facade under `zig/` and a runtime loader under `runtime/`.

## Build deviations

- `build.zig` compiles the C library directly instead of using upstream's CMake, Make, or autotools build.
- x86 and x86_64 use upstream's C-intrinsics kernels instead of its hand-written assembly. Each kernel is a separate object compiled for its own instruction set. The core and dispatcher use the requested target baseline.
- The build uses `-std=gnu11`; upstream requests C99 without extensions.
- `-fvisibility=hidden` applies only to shared builds. Upstream applies it to static and shared builds.
- The example is compiled, not installed. The Rust crate, `b3sum`, and benchmarks are not built or packaged.

## Support matrix

The build targets Zig 0.16.0 Tier 1 and Tier 2 platforms.

| Target family | Default SIMD kernels |
|---|---|
| x86, x86_64 | SSE2, SSE4.1, AVX2, AVX-512, selected by upstream CPU dispatch |
| AArch64 | NEON |
| Other families | None; the portable core is used |

| Platform | Shared-library files |
|---|---|
| ELF | `libblake3.so.0.1.8`, soname `libblake3.so.0`, and `libblake3.so` symlink |
| Darwin | `libblake3.0.dylib` and `libblake3.dylib` symlink |
| Windows | `blake3.dll` and `blake3.lib` |
| WASI | A dynamic request resolves to static delivery |

## Consumption

Use Zig 0.16.0 with a C compiler and libc. Zig supplies the C compiler and libc.

Add the package to `build.zig.zon`:

```zig
.dependencies = .{
    .blake3 = .{ .path = "../blake3" },
},
```

Import the `blake3` module from `build.zig`:

```zig
const dep = b.dependency("blake3", .{ .target = target, .optimize = optimize });
exe_mod.addImport("blake3", dep.module("blake3"));
```

The native artifact is `dep.artifact("blake3")` in bundled mode. The translated C header is available as `blake3.c`; it is not a separate module. Installation includes `include/blake3.h`, `lib/pkgconfig/libblake3.pc`, and the native library.

| Option | Effect |
|---|---|
| `-Dlinkage=static` | Static archive; default in bundled mode |
| `-Dlinkage=dynamic` | Shared library |
| `-Dportable=true` | Portable scalar core without SIMD kernels |
| `-Dsystem=true` | Use an installed `libblake3` and its `blake3.h`; this package builds and installs no library. Linkage defaults to dynamic in this mode. |
| `-Druntime=true` | Keep the library out of the Zig module and load a named provider at run time; the package still builds and installs its library. |

See `README.zig.md` for the facade and runtime-loader API.
