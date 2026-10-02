# UPSTREAM.md — what this fork is a fork of

## Upstream

| | |
|---|---|
| Project | BLAKE3, the hash function |
| Canonical repository | `https://github.com/BLAKE3-team/BLAKE3.git` |
| Pinned ref | tag `1.8.7` |
| Pinned commit | `f3149ec5bb5449af877ba20377a11008ff499fa2` |
| Version of the C library built here | `1.8.7` |
| Licence | `CC0-1.0 OR Apache-2.0 OR Apache-2.0 WITH LLVM-exception` |
| Copyright | Copyright 2019 Jack O'Connor and Samuel Neves |

Where each of those comes from, read out of the carried tree:

* The version string is `c/blake3.h:33` (`#define BLAKE3_VERSION_STRING "1.8.7"`)
  and `c/CMakeLists.txt:12-13` (`project(libblake3 VERSION 1.8.7 ...)`). It is
  the version of the C library, not a version of the Zig wrapper, and it is what
  `build.zig.zon` carries in `.version`.
* The licence string is `Cargo.toml:7` and, in prose, `README.md:191-197`:
  "This work is released into the public domain with CC0 1.0. Alternatively, it
  is licensed under any of the following: Apache 2.0, Apache 2.0 with LLVM
  exceptions". All three texts ship: `LICENSE_CC0`, `LICENSE_A2`,
  `LICENSE_A2LLVM`.
* The copyright line "Copyright 2019 Jack O'Connor and Samuel Neves" is the one
  the two Apache texts carry themselves (`LICENSE_A2:190`, `LICENSE_A2LLVM:189`).
  `Cargo.toml:4` names the same two people as the crate authors, and
  `README.md:68-74` names the four designers: Jack O'Connor, Samuel Neves,
  Jean-Philippe Aumasson and Zooko.

**Tag signature: not verified here.** No GPG key was consulted while this file was
written, and no git command was run at all, so nothing in this document is an
observation of the clone's own state. Treat the commit id and the archive digest
below as the provenance anchors, not a signature check.

## Archive receipt

The workspace delivery record `local://foundation-expansion-source-archives.json`
holds a SHA-256 receipt for the deterministic `git archive` stream of the **full
tree** at that commit. For this library it reads, verbatim:

```
b8352186f14559127a324333c3378f4208a2de9aea855746bf2fcd1f883efef1  -
```

The trailing `-` is `sha256sum`'s name for standard input: the digest is of the
archive stream as it was piped past the hasher, not of any file in this
repository. It was produced by the driver when the fork was imported. It is
recorded here so a later re-fetch can be compared against the same bytes.

The record above is a delivery receipt: it was produced when the fork was
imported, and it was not recomputed while this file was written. What *has* been
run here is the cheaper half of the same question — whether the bytes in this
working tree are still the pinned commit's, and whether the shipped subset still
matches `UPSTREAM.sha256`. Both were, and both are named under "Integrity".

## Import mechanism

A full clone of the canonical repository, so upstream's Git history is present.
The workspace delivery record states that every fork in this wave keeps the
upstream remote named `upstream`, a local `main`, and complete upstream history.
This fork adds no patch series on top of that history: the Zig package is a set
of new files in new regions, and the one upstream file that is edited at all is
`.gitignore`, which gains appended ignore entries (see `NOTICE.md`).

**Publication state.** This fork is local, uncommitted and unpublished. The
files it adds are untracked, nothing has been pushed, and no publication is
authorized in this expansion. Nothing in this file, and no remote it mentions,
asserts that a downstream repository exists.

## What this fork is

A Zig package that compiles upstream's own C library from `c/` in this
repository and publishes a small Zig facade over the translated `blake3.h`.
Nothing of the hash function is reimplemented, re-derived or reconfigured:
there is no generated table, no patched upstream source, and no download at
build time. The SIMD kernels upstream ships as one library per instruction set
become one object per instruction set here, each compiled for its own
instruction set alone, while the core and `c/blake3_dispatch.c` keep the
target's baseline so upstream's run-time CPUID dispatch still means something.
`NOTICE.md` lists every file this fork adds or edits, and `README.zig.md` §
"Build modes" describes the shapes in full.

## What is upstream's and is shipped unmodified

Everything named in `build.zig.zon` `.paths` that this fork did not write:

| Path | What it is |
|---|---|
| `c/` | upstream's C library, its CMake build, its examples and test harness, the hand-written assembly kernels for x86_64, the Rust FFI bindings directory and `c/README.md` — the whole directory travels, unmodified, so a dependent receives upstream's tree rather than a hand-picked subset |
| `test_vectors/test_vectors.json` | upstream's official known-answer vectors; `tests.zig` embeds this file and `smoke.zig` quotes from it |
| `LICENSE_A2`, `LICENSE_A2LLVM`, `LICENSE_CC0` | upstream's three licence texts, verbatim |
| `README.md` | upstream's project README, which carries the licence grant (`README.md:191-197`) |

## What is carried but is not part of the package

The Rust crate (`Cargo.toml`, `build.rs`, `src/`, `b3sum/`, `benches/`,
`reference_impl/`, `tools/`, `media/`), `CONTRIBUTING.md`, `.cargo/`,
`.git-blame-ignore-revs`, `test_vectors/`'s Rust harness, and upstream's own CI
(`.github/workflows/ci.yml`, `tag.yml` and the two Python helpers) stay in this
repository for provenance and audit. None of it is in `.paths`, none of it is
referenced by the build, and none of it is hashed by `UPSTREAM.sha256`; a
dependent that fetches this package will not receive it. Upstream's Rust CI is
not retargeted at this fork's infrastructure.

## Integrity

`UPSTREAM.sha256` holds 52 records: the SHA-256 of every upstream file this
package ships, one `<hex>  <path>` line each, in `sha256sum` format. Check it
with:

```
sha256sum -c UPSTREAM.sha256
```

Because the record names only files `.paths` ships, the same command works in a
cloned repository *and* in an unpacked package fetched by a dependent. The
`#`-prefixed lines in the file's header explain, per path, why anything is
excluded; the exclusions are `.gitignore` (appended to, therefore not
byte-identical), the fork's own files, and the record itself.

**How the digests were produced.** Each file was read as raw bytes with Bun's
`Bun.file(path).arrayBuffer()` and hashed with `crypto.createHash("sha256")`
from `node:crypto`, on 2026-10-01. No shell hashing command and no git command
was used to produce them.

**What the record establishes.** If it validates, the bytes a build compiles and
the fixture its tests read are the bytes this record pins, and any later edit to
one of those 52 files fails the check loudly.

**What it does not establish.** It is not a signature, not a Git object id, and
not a re-derivation from commit `f3149ec5bb5449af877ba20377a11008ff499fa2`: it
is a hash of this working tree.

**What has been run here.** Two commands, both green, both with a receipt:

* `sha256sum -c UPSTREAM.sha256` reported 52 records and no failures
  (`local://foundation-expansion-blake3-immutable-integrity-80.log`). It is the
  gate that keeps working in a dependent's unpacked package, because it names
  only files `.paths` ships.
* `git diff --exit-code f3149ec5bb5449af877ba20377a11008ff499fa2 -- c
  test_vectors LICENSE_A2 LICENSE_A2LLVM LICENSE_CC0 README.md` produced no
  output and exited 0 (`local://foundation-expansion-blake3-pristine-source-81.log`).
  That is the direct statement: the upstream files this package ships are the
  pinned commit's own bytes, not a reconstruction of them.

**What still needs a re-fetch.** The archive digest in "Archive receipt" is the
one link between this working tree and the commit id as a whole, and it was
recorded at import rather than recomputed here. Replaying it is the parent's job
and needs upstream fetched:

```
git -C <clone> archive --format=tar f3149ec5bb5449af877ba20377a11008ff499fa2 | sha256sum
```

The output must read `b8352186f14559127a324333c3378f4208a2de9aea855746bf2fcd1f883efef1  -`.

## Synchronising with a new upstream release

1. `git fetch upstream`, then check out the new tag and read its `c/blake3.h`
   `BLAKE3_VERSION_STRING`; that string, not the tag spelling, is the version.
2. Replace the `c/` directory wholesale from the new commit. Do not hand-patch
   upstream files to make a build problem go away.
3. Copy `LICENSE_A2`, `LICENSE_A2LLVM`, `LICENSE_CC0` and `README.md` from the
   new commit if they changed, and re-read the licence grant there.
4. Regenerate `UPSTREAM.sha256` over the same path set and bump the count in its
   header comment if it moved.
5. Re-check `build.zig` against the new tree: it names file names, upstream line
   references and upstream's own CMake recipes in its comments, and those are the
   things a release moves.
6. Bump `.version` in `build.zig.zon` to the new string, update the pin in this
   file and in `README.zig.md`, and add one numbered `CHANGELOG.md` entry.

## See also

* `NOTICE.md` — attribution, which of upstream's three grants covers which
  files, every file this fork adds or edits, and the Apache-2.0 obligations that
  attach to redistributing upstream's work.
* `README.zig.md` — how to build, import and call the package.
* `CHANGELOG.md` — numbered fork-only divergences.
* `FORK-NOTES.md` — the problems met while doing this and what was decided.
