# NOTICE

## Attribution

BLAKE3 is the work of the BLAKE3 team.

Copyright 2019 Jack O'Connor and Samuel Neves.

Upstream authors: Jack O'Connor and Samuel Neves. Designers: Jack O'Connor, Samuel Neves, Jean-Philippe Aumasson and Zooko.

Upstream: `https://github.com/BLAKE3-team/BLAKE3`, tag `1.8.7`, commit `f3149ec5bb5449af877ba20377a11008ff499fa2`.

## Licences and scope

Upstream states: “This work is released into the public domain with CC0 1.0. Alternatively, it is licensed under any of the following: Apache 2.0, Apache 2.0 with LLVM exceptions”. The three licence texts ship unchanged.

| Path | Licence or scope |
|---|---|
| `LICENSE_CC0` | CC0 1.0 Universal |
| `LICENSE_A2` | Apache License 2.0 |
| `LICENSE_A2LLVM` | Apache License 2.0 with the LLVM exceptions |
| `c/`, `test_vectors/test_vectors.json`, `README.upstream.md` | Upstream's three-way choice: `CC0-1.0 OR Apache-2.0 OR Apache-2.0 WITH LLVM-exception` |
| Fork-authored files listed below | `CC0-1.0 OR Apache-2.0 OR Apache-2.0 WITH LLVM-exception`; authorized in `FORK-LICENSE.md` |
| Original `.gitignore` entries `Cargo.lock` and `target` | Upstream |
| Fork-appended `.gitignore` entries | Fork-authored additions under the fork's grant |

Upstream files are unmodified except `.gitignore`. Its appended entries are `.zig-cache/`, `zig-out/`, `zig-pkg/`, `consumer/.zig-cache/`, `consumer/zig-out/`, `consumer/zig-pkg/`, `result`, `result-*`, `.devenv/`, `.devenv.flake.nix`, `.devenv.flakes/` and `devenv.local.nix`.

Fork-authored files:

`build.zig`, `build.zig.zon`, `zig/root.zig`, `zig/translate.h`, `runtime/loader.zig`, `runtime/sync.h`, `runtime/sync.c`, `runtime/generate.zig`, `runtime/graph.zig`, `runtime/library.zig`, `runtime/load_tests.zig`, `runtime/misuse.zig`, `tests.zig`, `smoke.zig`, `consumer/`, `cross-test.profile.sh`, `package.nix`, `flake.nix`, `devenv.nix`, `devenv.yaml`, `.envrc`, `UPSTREAM.md`, `UPSTREAM.sha256`, `NOTICE.md`, `FORK-LICENSE.md`, `README.md`, `README.zig.md`, `CHANGELOG.md` and `FORK-NOTES.md`.

`README.upstream.md` is upstream's README, preserved unchanged. The fork's files have no personal copyright identity assigned. `FORK-LICENSE.md` states the grant and Apache-2.0 obligations. `CHANGELOG.md` records the fork's changes.
