# NOTICE

## Upstream work

BLAKE3 is the work of the BLAKE3 team. The copyright notice the upstream licence
texts carry for themselves reads, in `LICENSE_A2:190` and in `LICENSE_A2LLVM:189`:

```
Copyright 2019 Jack O'Connor and Samuel Neves
```

`Cargo.toml:4` names Jack O'Connor and Samuel Neves as the authors of the
crate, and `README.upstream.md:68-74` names the designers: Jack O'Connor (`@oconnor663`),
Samuel Neves (`@sneves`), Jean-Philippe Aumasson (`@veorq`) and Zooko
(`@zookozcash`). Upstream repository: `https://github.com/BLAKE3-team/BLAKE3`;
this fork builds tag `1.8.7`, commit
`f3149ec5bb5449af877ba20377a11008ff499fa2`.

(`README.upstream.md` is upstream's own README, preserved byte-for-byte; see §
"Upstream README relocation" below.)

## The grants, and which applies where

Upstream offers three grants and states the choice in `README.upstream.md:191-197`: the
work "is released into the public domain with CC0 1.0. Alternatively, it is
licensed under any of the following: Apache 2.0, Apache 2.0 with LLVM
exceptions". All three texts ship in this repository, byte for byte, and are not
edited, shortened or restated here:

| File | Grant |
|---|---|
| `LICENSE_CC0` | CC0 1.0 Universal (the public-domain dedication) |
| `LICENSE_A2` | Apache License 2.0 |
| `LICENSE_A2LLVM` | Apache License 2.0 with the LLVM exceptions (`LICENSE_A2LLVM:204-218`) |

* Everything this fork did **not** write that is upstream's — the whole `c/`
  directory, `test_vectors/test_vectors.json`, the three licence texts and
  upstream's `README.upstream.md` — stays under that full upstream triple choice.
  Nothing here narrows it, re-grants it or restates it; a downstream may take
  any of the three.
* Everything this fork **did** write — the Zig build, the facade, the tests, the
  example, the consumer package, the cross-test harness profile, the runtime
  loader and its generated dispatch, the CI workflow, the Nix packaging and this
  documentation — is a new contribution by this fork, and upstream's three grants
  are upstream's to give over upstream's own work. **The licence for those files
  is stated in the next section.**

## Licence of this fork's own files — answered

**Status: source-confirmed.** Earlier revisions left the fork layer unassigned;
the owner has since authorized a per-project licence for fork-authored
additions matching the primary upstream terms. The grant is

```
CC0-1.0 OR Apache-2.0 OR Apache-2.0 WITH LLVM-exception
```

the same three-way choice upstream states for its own work. Upstream's authors
are not authors of these files, and no personal copyright identity was invented
for them. Upstream's files keep upstream's choice independently; nothing here
relabels a file carrying its own terms. `FORK-LICENSE.md` states the grant, the
authorization and the Apache-2.0 §4 and §3 obligations in full.

## Upstream README relocation

This fork's `README.md` is now the fork's own README: it opens with the
canonical order — current native-source deviations or None, current native-build
deviations with a dated history link, the current build/run/test matrix, then
consumption. Upstream's own README is preserved unchanged, byte for byte, as
`README.upstream.md`.

The preserved file has the same SHA-256 upstream's file has —
`37eb920117b5b75d2079862e1de630b892c5b0428abe6190eaf55778b0630826` — and that
digest is what `UPSTREAM.sha256` records, under the preserved path. Every citation
of upstream's README prose in this repository (the licence grant, the designer
list, the password-hashing warning, the `derive_key` context guidance) is
restated against `README.upstream.md`, and its line numbers are unchanged because
the bytes are unchanged. `README.upstream.md` is what a reader wants when the
question is what upstream says; `README.md` is what a reader wants when the
question is what this fork does differently.

## Distribution state

The fork is local, uncommitted and unpublished: nothing has been distributed yet.
That is not a reason to leave the question open, and it removes no obligation.
The obligations below are met for the works being redistributed regardless.

## Apache-2.0 obligations this repository already meets

If a downstream takes the Apache-2.0 grant for upstream's work, `LICENSE_A2` §4
requires a copy of the licence (shipped), a statement of the changes (§ "What
this fork changed" below, which is the notice §4(b) asks for), retention of
upstream's notices (§4(c), satisfied because no upstream file is edited), and,
where the work carries a `NOTICE` file, that downstream copies include the
attribution above (§4(d), this file). Those duties are owed to the works being
redistributed, so they are met whether or not this fork's own new files carry a
licence of their own.

### Patent grant

`LICENSE_A2` §3 grants a patent licence that terminates on patent litigation
against the work. Quoted from the shipped text (`LICENSE_A2:82-88`):

> where such license applies only to those patent claims licensable by such
> Contributor that are necessarily infringed by their Contribution(s) alone or
> by combination of their Contribution(s) with the Work to which such
> Contribution(s) was submitted. If You institute patent litigation against any
> entity (including a cross-claim or counterclaim in a lawsuit) alleging that the
> Work or a Contribution incorporated within the Work constitutes direct or
> contributory patent infringement, then any patent licenses granted to You under
> this License for that Work shall terminate as of the date such litigation is
> filed.

The grant quoted above is upstream's, over upstream's own contribution.
This fork has added no code to the compression function, the dispatch logic or
any SIMD kernel, so it makes no patent claim of its own and the risk it
introduces is only the risk of a modified distribution of upstream's work.

### The LLVM exception, if that grant is the one taken

Under `LICENSE_A2LLVM`, code embedded into an object form may be redistributed
without complying with §4(a), §4(b) and §4(d), and, when linked with GPLv2
software, §3 and §9 may be waived for the combined work
(`LICENSE_A2LLVM:204-218`). The changes listed below still exist and are still
recorded here; the exception relieves a downstream of carrying them into object
files, not of the record in this repository.

## What this fork changed

**No upstream source file, header, example, test harness, licence text or
fixture is modified.** `UPSTREAM.sha256` records the SHA-256 of every upstream
file this package ships; `sha256sum -c UPSTREAM.sha256` is the check, and it
covers the fixture `tests.zig` embeds as well as the sources the build compiles.
Both halves have been run here: the check reported 52 records and no failures
(`local://foundation-expansion-blake3-immutable-integrity-80.log`), and
`git diff --exit-code` against the pinned commit over `c`, `test_vectors`, the
three licence texts and `README.md` (upstream's README, before it moved to
`README.upstream.md`) produced no output
(`local://foundation-expansion-blake3-pristine-source-81.log`). `UPSTREAM.md` §
"Integrity" states what each of those does and does not prove.

One upstream file is edited, and only by appending:

| File | Change |
| `.gitignore` | upstream's two entries (`Cargo.lock`, `target`) are kept verbatim; the fork appends `.zig-cache/`, `zig-out/`, `zig-pkg/`, `consumer/.zig-cache/`, `consumer/zig-out/`, `consumer/zig-pkg/`, and then `result`, `result-*`, `.devenv/`, `.devenv.flake.nix`, `.devenv.flakes/` and `devenv.local.nix` so a Nix or devenv session cannot commit its own working files. Because the file is therefore not byte-identical to upstream's, it is deliberately absent from `UPSTREAM.sha256` and the append is recorded here instead. |

Everything else this fork adds is new, in new files:

| File | What it is |
|---|---|
| `build.zig` | Zig 0.16 build: compiles upstream's `c/` in-tree, compiles the SIMD kernels the architecture has as one object per instruction set, selects static or shared linkage with upstream's own ABI numbering, installs the native library, `blake3.h`, `libblake3.pc` and the carried licence material, and defines `test`, `smoke` and `check` |
| `build.zig.zon` | package manifest, dependency-free, `.paths` = what a dependent receives |
| `zig/root.zig` | the Zig facade: typed operations over `blake3_hasher`, plus `pub const c` for the raw translated surface |
| `zig/translate.h` | the single header `addTranslateC` translates; it includes `<blake3.h>` and copies no declaration |
| `runtime/` | the runtime-loading core and its generated dispatch: `loader.zig`, `sync.h`, `sync.c`, `generate.zig`, `graph.zig`, `library.zig`, `load_tests.zig`, `misuse.zig` |
| `tests.zig` | behavioural tests replaying upstream's published vectors, embedded with `@embedFile` |
| `smoke.zig` | the deterministic example behind `zig build smoke` |
| `consumer/` | a separate package that depends on this one by path and runs it |
| `cross-test.profile.sh` | harness settings only: `cross-test` discovers it from the package root and it names the standard `test` step over the full published platform matrix. It contains no upstream byte, builds nothing and grants nothing |
| `.github/workflows/verify.yml` | this fork's own verification workflow; upstream's `ci.yml` is left untouched |
| `package.nix` | one injected derivation taking `linkage`; it builds this tree's own `c/` through this tree's own `build.zig` with no sibling import, no host path and no build-time download |
| `flake.nix` | `packages.<system>.static` / `.shared` / `.default` from that one derivation, and a tools-only dev shell |
| `devenv.nix`, `devenv.yaml`, `.envrc` | the canonical development shell: tools and namespaced tasks only, lazy `outputs.static` / `outputs.shared`, never the SDK package itself |
| `README.upstream.md` | upstream's `README.md`, preserved byte for byte; not a fork-authored file and not a licence grant |
| `UPSTREAM.md`, `UPSTREAM.sha256`, `NOTICE.md`, `FORK-LICENSE.md`, `README.md`, `README.zig.md`, `CHANGELOG.md`, `FORK-NOTES.md` | provenance, licence and fork documentation |

Every file in that table is fork-authored and is covered by the grant stated
above, `CC0-1.0 OR Apache-2.0 OR Apache-2.0 WITH LLVM-exception`. `README.upstream.md`
is the one entry that is not: it is upstream's own README, carried unchanged,
and it keeps upstream's grant.

`runtime/` is eight new files. `loader.zig` is the reusable core — source and
error types, the platform `dlopen`/`dlsym`/`dlclose` or
`LoadLibrary`/`GetProcAddress` layer, the attempt state machine, and the
pre-readiness panic. `sync.h` and `sync.c` are the synchronization it calls,
compiled with the `blake3_rt` prefix. `generate.zig` is the host build program
that reads the real translate-c output and writes the dispatch. `graph.zig` is
`createCoreModule` and `createModule`, the two entry points `build.zig` calls.
`library.zig` is this library's descriptor: symbol set, ABI family note,
`validate`, `load`. `load_tests.zig` holds the loader's behavioural tests, run
against real providers rather than mocks. `misuse.zig` is a separate program
that the build runs as a child process to observe what a call before a successful
load does, which a test binary cannot observe about itself because the panic
stops it.

### Link metadata

`zig build install` writes `lib/pkgconfig/libblake3.pc`, at upstream's own name
and path (`c/CMakeLists.txt:366-368`). Its fields come from upstream's own
`c/libblake3.pc.in`; nothing is invented. `Name:` and `Description:` are
upstream's strings, `Version:` is formatted from the version read out of upstream
and `build.zig.zon`'s `.version` is checked against it at configure time
(`build.zig:1273-1276`), so they cannot drift apart silently, `Libs: -L"${libdir}" -lblake3` is upstream's
literal line and is identical in both linkages, and `Cflags:` is
`-I"${includedir}"` for the static variant plus `-DBLAKE3_DLL` for the shared
one — which is exactly what upstream appends under `BUILD_SHARED_LIBS`
(`c/CMakeLists.txt:139-145`). `Requires:` is empty because upstream fills it only
with oneTBB (`c/CMakeLists.txt:256`), and oneTBB is upstream's own default off
(`c/CMakeLists.txt:20`). There is no `Libs.private:` because upstream's template
has none and BLAKE3 depends on nothing but libc.

No CMake export set and no `blake3-config.cmake` are produced. Upstream's
`c/blake3-config.cmake.in` and `c/CMakeLists.txt:298-318` are CMake-internal
target exports; they are not link metadata a C or Zig consumer uses, and a
hand-written substitute would be a second packaging dialect upstream does not
ship.

## Cryptographic suitability

Upstream's own warnings are this fork's too, because the C library is upstream's
unmodified:

* **BLAKE3 is not a password hashing algorithm** (`README.upstream.md:80-83`).
  The keyed mode is a fast MAC, and the facade's `initKeyed` / `hashKeyed` are
  offered as such. Upstream recommends Argon2 for passwords, and so does this
  fork.
* **`derive_key` takes key material and a context string**, not a password. The
  context is a domain separator and is meant to be a short, hardcoded, globally
  unique string (`README.upstream.md`, "Key derivation"). The facade deliberately passes
  it by length, so a context containing a NUL byte is a different context rather
  than a truncation of the first one; `tests.zig` checks that against the raw
  C-string entry point.
* **Seeking is not a confidentiality feature.** `finalizeSeek` reads a window out
  of the extendable output at an offset; with a secret key a caller who publishes
  such an offset leaks key material, which upstream calls out explicitly
  (`c/README.md:239-241`).
