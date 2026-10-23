# Changelog

Fork-only changes to BLAKE3 1.8.7.

- Fixed runtime dispatch generation for duplicate `__root` declarations and nested variadic calls; provider validation failures now include the refusal text.
- Added selectable static or dynamic library linkage; static remains the default.
- Added explicit runtime-loaded provider support with `-Druntime=true`.
- Added Nix packages for static and shared builds, plus a development shell.
- Replaced the top-level README with fork documentation and preserved upstream's README as `README.upstream.md`.
- Licensed fork-authored files under `CC0-1.0 OR Apache-2.0 OR Apache-2.0 WITH LLVM-exception`.
- Added the dependency-free Zig package `blake3` for BLAKE3 1.8.7, with a typed facade over upstream's C library.
