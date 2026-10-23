# Upstream

## Identity

| | |
|---|---|
| Project | BLAKE3 |
| Canonical repository | `https://github.com/BLAKE3-team/BLAKE3.git` |
| Pinned ref | Tag `1.8.7`, commit `f3149ec5bb5449af877ba20377a11008ff499fa2` |
| C library version | `1.8.7` |
| Licence | `CC0-1.0 OR Apache-2.0 OR Apache-2.0 WITH LLVM-exception` |
| Copyright | Copyright 2019 Jack O'Connor and Samuel Neves |

Source obtained from a full clone of the canonical repository. The upstream Git history is retained.

## Shipped upstream files

| Path | Contents |
|---|---|
| `c/` | Upstream C library, CMake files, examples, tests, assembly kernels, Rust FFI bindings and `c/README.md`; unmodified |
| `test_vectors/test_vectors.json` | Upstream's published test vectors |
| `LICENSE_A2`, `LICENSE_A2LLVM`, `LICENSE_CC0` | Upstream licence texts, unchanged |
| `README.upstream.md` | Upstream `README.md`, preserved unchanged at this path |

## Upstream files not shipped

These upstream files remain in the repository but are outside `build.zig.zon` `.paths`: `Cargo.toml`, `build.rs`, `src/`, `b3sum/`, `benches/`, `reference_impl/`, `tools/`, `media/`, `CONTRIBUTING.md`, `.cargo/`, `.git-blame-ignore-revs` and the Rust harness under `test_vectors/`.

## Integrity record

`UPSTREAM.sha256` contains 52 SHA-256 records for shipped upstream files, in `sha256sum` format. Run `sha256sum -c UPSTREAM.sha256` to check them. The record excludes the modified `.gitignore`, fork-authored files and `UPSTREAM.sha256` itself.
