# CHANGELOG — fork-only divergences

Upstream's release history lives in its own repository. This file records **only**
what this fork changed relative to BLAKE3 `1.8.7`
(`f3149ec5bb5449af877ba20377a11008ff499fa2`), and it is written so a re-sync can
replay it. Numbers are stable identifiers; never renumber them.

Statuses below are the workspace's: **observed** means the driver ran a gate and
the output is in the named receipt; **source-confirmed** means the change was
read out of a file and involves no gate; **pending** means the change has landed
and no gate has looked at it yet. The current state of every gate, green or not,
is the one table in `README.zig.md` § "Verification status", and is not repeated
here.

This package is local, uncommitted and unpublished: nothing in this file has
been published, and no publication is authorized in this expansion.

## 1. Added the Zig 0.16 package

`build.zig`, `build.zig.zon`, `zig/root.zig`, `zig/translate.h`, `tests.zig`,
`smoke.zig`, `consumer/` and `.github/workflows/verify.yml` are new. New module:
`blake3`. New artifact: `libblake3.a` plus the installed `blake3.h`. The build
compiles upstream's `c/blake3.c`, `c/blake3_dispatch.c` and `c/blake3_portable.c`
from this repository and adds the SIMD kernels the target architecture has (see
entry 10 for how they are compiled). Nothing is downloaded, no upstream build
system runs, and `build.zig.zon` declares no dependencies. No upstream source
file is touched.

## 2. Chose the x86 C intrinsics kernels over upstream's hand-written assembly

Upstream prefers its own assembly on x86_64 and offers C intrinsics as an
alternative. This build compiles the four intrinsics kernels
(`c/blake3_sse2.c`, `c/blake3_sse41.c`, `c/blake3_avx2.c`, `c/blake3_avx512.c`).
Both flavours implement the same five instruction sets and are dispatched at run
time by `c/blake3_dispatch.c`; the assembly route needs a different source file
per platform and a working target assembler for each matrix target. The two
schemes must never be mixed — each defines the same `blake3_compress_in_place_*`
symbols — and this build picks one for the whole library.

Each kernel is its own object, compiled for its own instruction set alone, and
the library's own sources stay at the target's baseline (entry 10).

The C standard is pinned to `-std=gnu11` on every translation unit. Upstream asks
for C99 with extensions off; `c/blake3_dispatch.c` takes its C11 atomics path
whenever `<stdatomic.h>` is available, which is everywhere, and pinning the level
keeps `_Atomic int g_cpu_features` on its native spelling instead of on a
compiler extension of a C99 mode.

## 3. Appended Zig entries to `.gitignore`

Upstream's two entries (`Cargo.lock`, `target`) are kept verbatim; six Zig entries
are appended so an ordinary build does not dirty the tree. This is the only
upstream file this fork edits, and it is therefore deliberately absent from
`UPSTREAM.sha256`; the change is recorded in `NOTICE.md` instead.

## 4. Added the provenance and documentation set

`UPSTREAM.md`, `UPSTREAM.sha256` (52 records), `NOTICE.md`, `README.zig.md`,
`CHANGELOG.md` and `FORK-NOTES.md`. The integrity record hashes only the
upstream files this package ships, so `sha256sum -c UPSTREAM.sha256` works both
in a clone and in a package a dependent fetched. **Status: observed** — the gate
reported 52 records and no failures
(`local://foundation-expansion-blake3-immutable-integrity-80.log`), and
`git diff --exit-code` against the pinned commit over the same paths produced
no output (`…-pristine-source-81.log`).

This entry's "works both in a clone and in a package a dependent fetched" is now
observed on both halves rather than argued from the manifest: entry 13 gates the
materialised package and runs the record inside it.

## 5. Repaired the build script's option literal

**Condition.** Zig 0.16 rejected the option declaration written as an anonymous
struct literal immediately followed by a second `.{...}`.

**Symptom.** `build.zig:190:2: error: expected ';' after declaration`, with the
offending text `}.{`. Every gate failed at configure time with exit code 2 —
install, both test modes, smoke and the consumer alike
(`local://foundation-expansion-blake3-install.log`, `-test-debug.log`,
`-test-releasesafe.log`, `-smoke.log`, `-consumer.log`).

**Fix.** A named type with a typed literal. **Status: observed** — no later run
reports this error; each proceeds far enough to fail later in the pipeline.

## 6. Replaced `std.fmt.bytesToHex` with a bounded format

**Condition.** `std.fmt.bytesToHex(input, case)` returns `[input.len * 2]u8`, so
its result length must be known at comptime. Three private helpers format a
digest whose length is a runtime slice length.

**Symptom.** `lib/std/fmt.zig:1156: error: unable to evaluate comptime expression`,
instantiated at `tests.zig:151`, `smoke.zig:133` and `consumer/src/main.zig:131`
(`local://foundation-expansion-blake3-test-debug.log`, `-smoke.log`,
`-consumer.log`).

**Fix.** Each helper formats into its own stack buffer with
`std.fmt.bufPrint("{x}", .{digest})`, sized `2 * len + 1`, and compares the
resulting hex text with the published answer. No allocation, and the buffer is
still an ordinary fixed-size local.

**Status: observed** — `test` (Debug), `test` (ReleaseSafe) and `test
-Dportable=true` all exited 0 afterwards (`…-initial-debug-12.log`,
`…-test-releasesafe-29.log`, `…-portable-debug-32.log`).

## 7. Fixed the array-to-slice coercion in the example

**Condition.** An array *value* does not coerce to a slice; a *pointer* to an
array does. `blake3.hash(three_byte_input, &digest)` passed
`[_]u8{0, 1, 2}` where `[]const u8` was expected.

**Symptom.** `smoke.zig:92:17: error: array literal requires address-of operator
(&) to coerce to slice type '[]const u8'`. This was the only failing translation
unit, so it red-lined exactly the gates that build the example: `zig build`
(`…-install-28.log`), `zig build smoke` (`…-smoke-30.log`) and
`zig build smoke -Dportable=true` (`…-portable-smoke-33.log`), all exit 1. The
test and consumer gates were unaffected.

**Fix.** `&three_byte_input` at the call site; the constant stays an array.

**Status: observed** — `zig build smoke` exited 0 afterwards
(`…-repaired-smoke-35.log`), and `zig build` and `zig build smoke
-Dportable=true` have been run since this fix, both green
(`local://foundation-expansion-blake3-isa-native-install-128.log`,
`…-isa-portable-smoke-131.log`).

## 8. Strengthened the reset test's poison

`tests.zig` now poisons the hasher with two whole chunks plus one byte
(`2 * chunk_len + 1`, i.e. 2049) before `reset`, instead of a shorter buffer. The
longer poison is what makes the test meaningful: it reaches past the buffered
block *and* past a chunk boundary, so a reset that left a chaining value on the
stack would produce a wrong digest rather than accidentally agreeing.

**Status: observed.** The current file passes in Debug, in ReleaseSafe and with
`-Dportable=true`, 6/6 each
(`local://foundation-expansion-blake3-api-debug-proof-118.log`,
`…-isa-native-safe-119.log`, `…-isa-portable-debug-130.log`).

## 9. Added the derive-key context test

A new test compares the facade's length-passing context handling against the raw
`blake3_hasher_init_derive_key` path through `pub const c`, and checks that a
context holding an embedded NUL derives something different from its own
truncation at that NUL — the failure a wrapper that passed the context as a C
string would produce.

**Status: observed**, for the same reason as entry 8: the sixth test is one of
the six those three runs counted. `FORK-NOTES.md` §11 says why the comparison
it makes is the falsifiable one.

## 10. Compiled each x86 SIMD kernel as its own object on its own target

**Condition.** The four intrinsics kernels were four more sources on the
library's one C module, which is how upstream's CMake build puts them behind a
`-m` flag.

**Symptom.** Everything on the build host passed and the two x86 cross targets
did not: 114 errors for `x86_64-linux-gnu`, 54 for `x86_64-windows-gnu`, of the
shapes `AVX vector return of type '__m256i' … without 'avx' enabled changes the
ABI` and `'__builtin_ia32_pblendw128' needs target feature sse4.1`
(`local://foundation-expansion-blake3-target-x86_64-linux-gnu-72.log`,
`-target-x86_64-windows-gnu-75.log`, both exit 1).

**Fix.** `add_x86_kernel` compiles each kernel into an object of its own,
against a target taken from the caller's and pinned to `cpu_model = .baseline`
with exactly that row's features and nothing else. The core sources and
`c/blake3_dispatch.c` keep the caller's baseline, so upstream's run-time CPUID
dispatch still selects a kernel the CPU reports having, and no kernel object
carries instructions beyond its own instruction set. No `-m` flag is passed
anywhere now.

**Status: observed** — both targets compile, four kernel objects each, 14/14
steps: `local://foundation-expansion-blake3-isa-target-x86_64-linux-gnu-114.log`
and `-isa-target-x86_64-windows-gnu-115.log`. `FORK-NOTES.md` §9.

## 11. Gated the installed C surface on upstream's published answers

**Condition.** `.github/workflows/verify.yml` compiled a C program against the
installed header and archive, then checked it by comparing the version string
the linked library reported against a pinned constant and by comparing two calls
into this same build against each other.

**Why that was not a gate.** Both comparisons pass for a library that is
consistently wrong: a build reporting the wrong version, or one whose every mode
is off by the same amount, clears both. `AGENTS.md` §7 removes permanent tests
of exactly that shape.

**Fix.** The C gate now calls every hasher routine the header declares except
the oneTBB entry this build never defines, so a declaration with the wrong type
fails to compile and one the archive does not define fails to link, and holds
every answer it checks to upstream's published
`test_vectors/test_vectors.json`: the `key` and `context_string` fields and the
complete 131-byte extended outputs of the `input_len` 0 and `input_len` 3 cases
in all three modes. It exercises segmented updates,
`blake3_hasher_finalize_seek` at offset 65 — one byte into the second 64-byte
block — and `blake3_hasher_reset` after two whole chunks plus a byte of poison,
in each of the three modes. The version is printed by `smoke.zig` and compared
to nothing.

**Status: observed** — installed into a scratch prefix outside the tree
(`local://foundation-expansion-blake3-installed-artifact-gruenau8-187.log`), then
compiled against the installed `blake3.h`, linked against the installed
`libblake3.a` and run: exit 0, `public C surface compiled, linked and ran`
(`…-installed-C-surface-190.log`). `FORK-NOTES.md` §10.

## 12. Withdrew the invented licence grant for this fork's own files

**Withdrawn.** `NOTICE.md`, `README.zig.md` and earlier revisions of this file
stated that everything this fork wrote — the build graph, the facade, the tests,
the example, the consumer package and this documentation — is "offered under the
Apache-2.0 grant in `LICENSE_A2`". That borrowed a licence because its text
happens to ship here: `LICENSE_A2` is upstream's grant over upstream's own work,
it says nothing about files upstream never saw, and nobody in this repository
has authority to extend it to them.

**Now.** The fork's own files carry no stated licence here, and `NOTICE.md`
records that as unassigned rather than answering it. Upstream's triple choice —
CC0 1.0, Apache-2.0, or Apache-2.0 with the LLVM exception — stays exactly as
upstream states it, and the Apache obligations that attach to redistributing
upstream's work are met either way. The choice belongs to this fork's owner and
belongs in `NOTICE.md` when it is made. **Superseded in part by entry 17** (2026-10-04):
the owner made that choice, and the licence is now stated rather than
unassigned. What this entry withdrew — borrowing `LICENSE_A2` for files upstream
never saw — remains withdrawn.

**Status: source-confirmed.** A change of record, not of code: no gate is
involved and none is claimed.

## 13. Gated the shipped package, not only this working tree

**Condition.** Entries 1 and 4 make claims about what a *dependent* receives:
that `.paths` names every file the package needs, and that
`sha256sum -c UPSTREAM.sha256` "works both in a clone and in a package a
dependent fetched". Every gate until now ran against this working tree, where
the whole repository is present whatever `.paths` says, so both claims were
arguments from the manifest rather than observations. Nothing in the build
reads `.paths` at build time — a path dependency is used in place — which means
the only thing that exercises `.paths` is a real materialisation of the package.

**Status: observed.** The driver ran `zig fetch` over this package directory
from an external approved scratch build root
(`/home/tmp2/gertullj/scratch/foundation-libs/session-01a0f400/package-fetch`),
not from inside the repository: exit 0, and the package identity it printed is
`blake3-1.8.7-V1p9dYNCFgANxaiTyV6hzK0BJYW2PtTiCwoUVZ3CtZBz`
(`local://foundation-expansion-blake3-external-driver-package-fetch-315.log`).

**Kept as history.** All three of those runs predate `cross-test.profile.sh`
joining `build.zig.zon`'s `.paths`, so they record an earlier `.paths` and are
no longer the current state of this package; entry 15 says what is pending in
their place.

Two further gates ran **inside that materialised copy**, not here:

* `sha256sum -c UPSTREAM.sha256` — exit 0, 52 records, every line `<path>: OK`,
  nothing failed and nothing missing (`…-materialized-package-integrity-329.log`).
  This is what binds entry 4's "works in a package a dependent fetched" to a
  run: all 52 records — the whole `c/` directory, `test_vectors/test_vectors.json`,
  the three licence texts and upstream's `README.md` — are files `.paths`
  delivers, so `.paths` is complete against the record and not only against this
  tree.
* `consumer/` in the fetched copy, `zig build run` — exit 0. It printed
  `blake3 consumer`, `linked C library reports version 1.8.7`, the published
  digests for the empty input, for `00 01 02`, after `reset`, at a 131-byte
  extended output and at seek 96, and closed on
  `every digest matched the published vectors`
  (`…-materialized-package-consumer-330.log`). The facade, the C core, the
  translated header and the embedded fixture therefore resolve through `.paths`
  alone, in a package that did not write this one.

**What this entry does not close.** The fetch source was this local directory,
so no remote URL, no registry index and no published `.hash` was exercised, and
no publication is authorized: nothing here is evidence about a published
release. The materialised copy is not a Git clone, so entry 4's `git diff
--exit-code` half (`…-pristine-source-81.log`, exit 0, no output) remains a
separate observation about this working tree — a direct diff against the pinned
commit, not a replay of `git archive` and not a CI run. Two earlier attempts at
materialising this package failed with `IllegalFileTypeInPackage` over both the
directory and a tar of the same tree (`…-materialized-package-fetch-257.log`,
`…-materialized-tar-package-fetch-276.log`); the runs above supersede them and
are recorded here as history, not as current state. `-Dsystem=true` remains
ungated and unclaimed.

---

## 14. Gave the package a full-matrix `cross-test` gate, and checked the kernel selection against 32-bit and big-endian targets

**Condition.** Entry 13 is the last gate that has observed this package, and
every cross-target gate so far is `zig build check`, which compiles and runs
nothing. Its six targets are all 64-bit apart from `wasm32-wasi`. The gate that
executes `tests.zig` per platform had no configuration in this package at all,
and the platforms it names include rows the six-target list never reaches —
`x86-linux`, `thumbeb-linux`, `riscv32-linux`, `hexagon-linux` on one side,
`aarch64_be-linux`, `s390x-linux`, `powerpc-linux` on the other — which is
where a kernel-selection mistake becomes a compile error rather than a wrong
digest.

**Change.** `cross-test.profile.sh` is new and is listed in
`build.zig.zon` `.paths`. It is settings only, and deliberately almost empty:
`CROSS_BUILD_STEP=test` and `CROSS_BUILD_TIMEOUT=900`, both the harness's own
defaults written out so the gate is readable without reading the harness (entry
15 raises that number and adds the per-test one this entry left unset). It
sets no `CROSS_MATRIX` and no `TARGETS`, so the matrix is the whole published
Zig 0.16.0 Tier 1/2 table; it passes no `-Dtarget`, `-Doptimize` or
`-Dportable`, because the harness manages `-Dtarget` itself and rejects it in
`CROSS_BUILD_ARGS`; it names no compiler, cache or output path; it defines no
`cross_build_command` or `cross_artifact`, so the harness stays in its standard
`zig build test` mode over this package's own graph; and it does not set
`CROSS_REQUIRE_RUNNERS=1`, because a platform with no runner on the host is
already recorded as explicit `build_only` coverage and demanding a runner would
report a missing runtime as a broken target.

`build.zig` needed no functional change to serve it. `build()` resolves
`-Dtarget` into the same graph the host build uses, and the `test` step calls
`b.addRunArtifact` on that graph unconditionally, which is exactly what the
harness needs in order to decide per target between running the binary,
prefixing an emulator, and skipping the run while keeping the compile
dependencies. Only the module doc comment changed.

**What was checked, and what it found — `SOURCE-CONFIRMED`, see `FORK-NOTES.md`
§ 12.** Kernel selection for big-endian AArch64 is already correct, and it is
correct because Zig 0.16.0 gives every big-endian family its own `Cpu.Arch`
value: `Simd.for_arch` matching `.aarch64` is little-endian only, so
`aarch64_be-linux` and `aarch64_be-netbsd` take `.none` and never compile
`c/blake3_neon.c`, which refuses big-endian at its own line 4. 32-bit x86 taking
all four intrinsics kernels including AVX-512 is upstream's own recipe
(`c/CMakeLists.txt:31,106-114,181-199`), not an extension here. 32-bit ARM
deliberately takes the portable core rather than upstream's `neon-intrinsics`
choice for an ARMv8 name, because `c/blake3_neon.c` uses aarch64-only
intrinsics. Nothing in the C core reads an endian macro or assumes a pointer
width.

**What did not change.** `c/` is byte-identical and `UPSTREAM.sha256` is
untouched. The six-target `check` matrix is exactly as it was. `tests.zig`
still holds the same six behavioural tests against upstream's published
vectors; none was added, removed or re-pinned, because nothing observable
changed and a declaration or wiring test would not be one. The profile carries
no licence grant of its own and is recorded in `NOTICE.md` among the
fork-authored files.

**Status: observed.** `cross-test` ran the full matrix from this package root
twice. The first run (`20261002-040256-44888-16144`) compiled all 53 targets
and failed two AArch64 rows on the harness's 300-second per-test default, not on
an answer; entry 15 raises the deadlines, and the second run
(`20261002-055258-61044-19309`) built all 53 and executed this package's six
tests 6/6 on 20 of them, with 33 `build_only` and zero failures
(`local://foundation-cross-test-corrected-blake3.json`, one log per target).

The 32-bit and big-endian platforms reasoned about below are now compiled by an
observed gate rather than only read: `x86-linux` took all four intrinsics
kernels including AVX-512 and still passed 6/6, and `aarch64_be-linux`,
`aarch64_be-netbsd`, `arm-linux`, `thumb-linux`, `thumbeb-linux`,
`riscv32-linux`, `hexagon-linux`, `s390x-linux` and `powerpc-linux` each report
`blake3: portable core only` in
`local://foundation-cross-test-corrected-blake3-<target>.log`. The big-endian
AArch64 rows therefore never reach `c/blake3_neon.c`, which is what the arch
tag argument predicted.

---

## 15. Raised the matrix deadlines so AArch64's Debug vectors finish under QEMU

**Condition.** Entry 14 set `CROSS_BUILD_TIMEOUT` and left the per-test deadline
alone, so the harness's 300-second default applied to each individual test case.
Under QEMU-user an AArch64 Debug run replays upstream's 35 published vectors —
inputs to 102400 bytes in all three modes, each compared as a complete 131-byte
extended output — at a fraction of native speed.

**Symptom.** Two of 53 targets in the first full matrix
(`20261002-040256-44888-16144`) were red, and both were red on a deadline:

```
aarch64-linux      'tests.test.streaming is invariant to how the input is split at block and chunk boundaries' timed out after 5m368.911ms
                   Build Summary: 4/6 steps succeeded (1 failed); 5/6 tests passed (1 timed out)
aarch64_be-linux   'tests.test.one-shot helpers agree with the published digests' timed out after 5m248.837ms
                   'tests.test.streaming is invariant to how the input is split at block and chunk boundaries' timed out after 5m112.063ms
                   Build Summary: 4/6 steps succeeded (1 failed); 4/6 tests passed (2 timed out)
```

Both exits 1 (`local://foundation-cross-test-matrix-blake3-aarch64-linux.log`,
`…-matrix-blake3-aarch64_be-linux.log`). Those two targets were the only
failing ones in the run, every test case that finished passed, and no test was
shortened, dropped or re-pinned to get past them.

**Fix.** `CROSS_BUILD_TIMEOUT=3600` for one target's compile plus complete run,
and `CROSS_TIMEOUT=1800` for one test case. Nothing else moved: same Debug
graph, same six tests, same vectors, no target list and still no `-D` option,
and `cross-test --list` and `cross-test --no-profile --list` still name the same
53 platforms from this directory.

**Status: observed.** The corrected run `20261002-055258-61044-19309` built all
53 targets with exit 0, executed the six tests 6/6 on 20 of them, recorded 33
`build_only`, and failed none; the two AArch64 rows report
`run test blake3-tests 6 pass (6 total) 1m`. Receipts:
`local://foundation-cross-test-corrected-blake3.json` for the per-target record
and `local://foundation-cross-test-corrected-blake3-<target>.log` for each
target's own build summary. The profile's own syntax and matrix listings are
`local://foundation-cross-test-profile-blake3-syntax.log`,
`…-list_profile.log` and `…-list_no_profile.log`, all exit 0.

**What did not change.** No C source, header, fixture, test, example, facade or
licence text: `c/` is byte-identical and `UPSTREAM.sha256` is untouched.
`build.zig` gained nothing for this; only `cross-test.profile.sh` changed. The
same wave re-ran the native gates on the current tree — `zig build test smoke
install -Doptimize=Debug` 19/19 steps and 6/6, `zig build test smoke
-Doptimize=ReleaseSafe` 17/17 and 6/6, and `consumer/`'s `zig build run` 14/14
(`local://foundation-cross-test-stable-blake3-native-Debug.log`,
`…-ReleaseSafe.log`, `…-consumer.log`) — and all six compile-only `check` targets
(`local://foundation-cross-test-baseline-blake3-<target>.log`, exit 0 each).
The `-Dportable=true` rows were not re-run and keep their 2026-10-01 receipts.

**Still pending.** The package round. The fetch of this package, the 52-record
check inside that materialised copy and `consumer/` inside it were all taken
before `cross-test.profile.sh` entered `.paths`, so they stand as history; a
final filtered fetch of the current tree and those two gates inside it have not
run, and nothing about the current `.paths` is claimed until they do.

## 16. Zig API contract alignment — 2026-10-03

**Condition.** A constructed `Hasher` is a value with independent copies;
input and output slices still carry the native aliasing obligations.
The former adjacent `c` registration exposed an internal build dependency.

**Fix.** Document constructed state, copies, borrowing, output mutation,
native allocation and concurrency at the authored declarations. Keep raw C
through `blake3.c`; remove the separate internal module registration. Supply
a complete module example and correct the version/header citations.

**Verification and bound.** Zig 0.16.0, native Linux x86-64: install,
Debug/ReleaseSafe tests, smoke, the separate package consumer and the module
example pass. The published compile-only `check` matrix passes. Foreign
runtime, portable-option and hosted CI results are not refreshed by this entry.
No native source, header, generated binding or provenance pin changed.


## 17. Made the owner's licence grant for the fork layer — 2026-10-04

**Condition.** Entry 12 withdrew an invented Apache-2.0 offer for the files this
fork writes and recorded the question as unassigned, because nobody in the
repository had authority to make the grant.

**Fix.** The owner authorized a per-project licence for fork-authored additions,
matching the primary upstream terms where appropriate. The grant is now made and
recorded: `CC0-1.0 OR Apache-2.0 OR Apache-2.0 WITH LLVM-exception`, the same
three-way choice upstream states for its own work. All three texts already ship
verbatim, so nothing was written, summarised or edited to carry it. The SPDX
identifier for every file this fork authors, including the new runtime and Nix
files, is that whole expression.

The grant does not claim upstream authorship, does not narrow upstream's own
choice, and does not relabel any file that carries its own terms. No personal
copyright identity was invented for the fork layer. `FORK-LICENSE.md` states the
grant and the authorization; `NOTICE.md` carries the inventory and the Apache-2.0
§4/§3 obligations.

**Status: source-confirmed.** A change of record, not of code. Entry 12's
withdrawal stands as a withdrawal of *that* offer; this entry records what
replaced it.

## 18. Gave this fork its own README, in the canonical order — 2026-10-04

**Condition.** `README.md` was upstream's own README, so the name a dependent
sees first described upstream rather than this fork, and the fork's actual
deviations, support matrix and consumption instructions were scattered across
`README.zig.md` and the provenance files.

**Fix.** `README.md` is now this fork's README, ordered: current native-source
deviations, current native-build deviations with a dated history link to
`CHANGELOG.md`, the current build/run/test matrix, then consumption.
`README.zig.md` remains the interface documentation alone. Upstream's README is
preserved unchanged, byte for byte, as `README.upstream.md`.

**Consequences outside this file's ownership.** `UPSTREAM.sha256` records
upstream's README digest under the preserved path (`README.upstream.md`), the
same bytes and the same SHA-256; every citation of upstream's README prose now
names `README.upstream.md` with unchanged line numbers. `build.zig.zon`
`.paths` must list `README.upstream.md` and the new files; that is the build
owner's edit.

**Status: pending-verification.** The relocation moved a path, not a byte, and
the digest is unchanged, but `sha256sum -c UPSTREAM.sha256` has not been re-run
against the current tree.

## 19. Added the standalone Nix and devenv packaging — 2026-10-04

**Condition.** This SDK had no Nix packaging, so it was not standalone: a
consumer had no source-built package to depend on and no canonical way into a
development shell.

**Fix.** `package.nix` is one source-only derivation consumed by both `flake.nix`
and `devenv.nix`. It builds this tree's own `c/` through this tree's own
`build.zig`, imports nothing from a sibling directory, names no host account,
node or store path, reads no environment variable at evaluation time and
downloads nothing at build time. The flake exposes `static` and `shared` as
separate variants of that one derivation and resolves `default` to the static
one, preserving this SDK's existing linkage policy. `devenv` is the canonical
development shell: tools and namespaced tasks only, with lazy `outputs.static`
and `outputs.shared` calling the same derivation, so entering the shell never
builds the library. One writer per installed path — the build graph installs the
native library, the public header, `libblake3.pc` and the six licence and
provenance records under `share/licenses/blake3/`, and the derivation writes
none of them.
Each task body now opens by changing to this module's own directory — devenv runs
a task with the caller's working directory, which is not this SDK — and every
`zig build` in it carries `-j8`, `--summary all`,
`--cache-dir "$ZIG_LOCAL_CACHE_DIR/blake3"` and
`--global-cache-dir "$ZIG_GLOBAL_CACHE_DIR"`, so no build resolves a cache of
its own and this SDK's `.zig-cache` is never used. A cache variable the caller
exported is used unchanged; a missing one is filled from `XDG_CACHE_HOME`, then
from `TMPDIR`, and the task refuses to run before the compiler when neither names
a location — the fills are in the bodies, not only in `enterShell`, because
`devenv tasks run --mode single <name>` does not run it. `sdk:build`, whose step
is the install step, also passes `--prefix
"$ZIG_LOCAL_CACHE_DIR/blake3-prefix"` and so writes no `zig-out/` either; no other
task installs, so no other task carries a prefix. No build graph, task name,
linkage, mode, argument forwarding or install layout changed, and no task has
been run since this change.

**What is deliberately absent.** `devenv.lock` is the driver's to generate from
observed evaluation; an invented narHash would fabricate exactly the digest a
lock file exists to record. `flake.lock` is present, is named in `build.zig.zon`
because it exists, and carries one `github:NixOS/nixpkgs` pin at revision
`c7def046b9a883d46974757852106483d741586f`; it is a lock record rather than
authored material, and `.gitignore` keeps it because it is a real input that
belongs to the driver. The derivation never passes `-Dsystem`, so a system library
can never stand in for a source result, and never passes `-Druntime`, so it makes
no claim about the runtime route.

**Status: pending-verification.** Neither derivation has been evaluated or built,
and no output layout or dependency record has been inspected.

## 20. Added the runtime-loading route — 2026-10-04

**Condition.** A consumer could only reach this library by linking what this
tree compiles. There was no way to name a provider at run time.

**Fix.** `-Druntime=true`, declared in `build.zig`, default off, and independent
of `-Dlinkage`. Under it nothing is linked into the module — neither the archive
this tree compiles nor an installed system library — and each selected native
entry point dispatches through one process-lifetime table filled by an explicit
`load`. The library is still built and installed, so a caller may name a
provider this tree did not build and may equally name the one it did; the
configure-time line says which situation a build is in. The source is explicitly
`.path` (an absolute file path) or `.system` (a basename handed unchanged to the
platform loader); there is no path-to-system fallback and no automatic retry.
The files are `runtime/loader.zig`, `runtime/sync.h`, `runtime/sync.c`,
`runtime/generate.zig`, `runtime/graph.zig`, `runtime/library.zig`,
`runtime/load_tests.zig` and `runtime/misuse.zig`.

**Two boundaries this entry owns.** First, **one core-module instance per
build**: `graph.createModule` creates the single core module the generated
dispatch uses and re-exports `LoadSource`/`LoadError` from it, so the runtime
branch of `build.zig` imports only `c` and adds no `rt` import of its own. A
second core module created for the facade would make its `LoadSource` a nominal,
different type, and `blake3.load(source)` would hand the facade's type to a
function expecting the dispatch's. The linked branch has no dispatch, so there
`createCoreModule` is imported as `rt` and the facade picks with a comptime
branch on `runtime_loaded`. Second, the `blake3_rt` synchronization prefix is
written twice by necessity — as `-DRT_SYNC_PREFIX` in `graph.zig` and as bound
symbol names in `library.zig` — so the two must be changed together. **A second
independent instance of this SDK in one binary needs both changed**; that is a
real limit of this design, recorded here rather than discovered at link time.

**The ABI boundary is stated, not assumed.** The provider must export the nine
public entry points of the plain C library; `blake3_hasher_update_tbb` is not
among them because it sits behind `BLAKE3_USE_TBB`. It must have been compiled
against the same `blake3.h` and the same `BLAKE3_MAX_DEPTH`, `BLAKE3_BLOCK_LEN`,
`BLAKE3_OUT_LEN`, `BLAKE3_KEY_LEN` configuration. Symbol lookup and a version
string are not ABI proof. The loader allocates nothing, and the only libc
dependency is the platform loader itself, so a `-static` binary cannot use this
route.

**Status: pending-verification.** Nothing here has been executed. No
runtime-loaded consumer, no failure, retry, idempotence, provider-change,
atomic-publication or release-mode panic check has run, and no receipt exists.

**What the build gates, and what it does not.** `runtime/load_tests.zig` is an
`addTest` root wired only under `-Druntime=true` behind the step
`runtime-test`; its own comptime guard refuses to compile against a linked
module, so wiring it unconditionally would wire a compile error. It reads
`BLAKE3_TEST_PROVIDER` and `BLAKE3_TEST_ALIEN` from the caller's environment,
because `Step.Run` takes only literal strings in an environment map
(`Run.zig:595-598`) and there is no API for a build-time-resolved path there;
without them the step fails rather than skipping. `runtime/misuse.zig` is
compiled in **both** configurations — its `linked-load` mode asserts the message
a linked build produces — and is install-depends-on rather than an installed
deliverable. The step `runtime-misuse` runs `after-load <provider>` with
`expectExitCode(0)`: **the control only.** `pre-load` and `linked-load` are
compiled everywhere but no build step runs them, because their assertion is
that the program stops and `Step.Run` exposes only `expectExitCode(u8)`
(`Run.zig:628-631`) — writing down an exit code nothing has observed would be a
fabricated gate. Those two modes are driver-run and driver-observed.
`zig build check -Druntime=true` does compile both programs for all six matrix
targets, because `add_target_check` builds through the same `add_graph`.


## 21. Made static and shared delivery selectable — 2026-10-04

**Condition.** The build hard-coded `.linkage = .static`. A consumer that needed
a loadable shared object — or a runtime-loaded route, which needs one on disk —
had no way to ask for it, and the only artefact this SDK could produce was an
archive.

**Fix.** `-Dlinkage=static|dynamic`, defaulting to `static`. The default is what
the SDK produced before the option existed, so no existing consumer's linkage
changes and no recorded gate result is invalidated by the option's arrival. The
shared variant is a real shared object: PIC on the core and on every
independently compiled per-ISA kernel object, real exports, and the complete
closure — core, dispatch, and each kernel object — inside one artefact. No
source is dropped to make it link, and the installed `blake3.h` is identical in
both variants.

**One deliberate deviation from upstream, on the static side.**
`-fvisibility=hidden` reaches the shared delivery only. Upstream sets
`C_VISIBILITY_PRESET hidden` unconditionally (`c/CMakeLists.txt:150-155`), so
upstream's own static archive carries the flag and this one does not. The reason
is cost, not principle: `static` is the delivery every gate in this repository's
recorded history observed, and adding a flag to that command line would perturb a
verified build for a property that is inert there — visibility governs a dynamic
symbol table and an archive has none, so a hidden symbol in an archive is still
linkable. The artifact that actually has an export surface, the shared object,
matches upstream exactly. The static build's C command line is therefore
unchanged from before this option existed. `FORK-NOTES.md` §19 has the finding
and the reasoning.

**Status: pending-verification, and narrower than it was.** A shared object has
now been produced: all four optimize modes of `20261004T233628757747Z-69351`
built and installed one, and the loader opened that exact `libblake3.so.0.1.8` in
all eight `-Druntime=true` cells of `20261004T232823091897Z-23133`, which is
evidence that the export surface carries what this facade calls. The export table
and the relocations are still gates the driver owes; nothing about the shared
variant's *contents* is claimed until they run.


## 22. Repaired the dispatch root, nested variadic tuples and the refusal print — 2026-10-04

**Condition.** `runtime/generate.zig` copied the translation's `const __root =
@This();` prologue into the dispatch and, separately, wrote a `__root` of its own
whenever a declaration copied in here referred to one. It also held one pending
"write an empty tuple before this `)`" index at a time, so a variadic call
inside another variadic call took the outer one's wait away from it.

**Symptom, reproduced before this change** by running the generator's own CLI
over two scratch inputs. `core-root-regression-input.zig` — the prologue, one
`pub extern fn get() callconv(.c) c_int`, one `pub inline fn helper()` returning
`__root.get()` — produced a dispatch carrying `const __root = @This();` twice, at
lines 81 and 158, which `zig ast-check` rejects as a duplicate member.
`core-varargs-regression-input.zig` — a variadic `inner` and `outer`, and a
helper returning `outer(inner(7))` — produced `outer(inner(7, .{}))`: only the
inner call was given the tuple that both wrappers take.

**Fix.** Planning classifies the prologue as a class of its own, on the same
`isThisPrologue` answer the patch already asks for, so the dispatch writes one
`__root`, in the preamble, only when a copied declaration refers to one, and the
patched translation's line is still repointed at the dispatch. `writeCopied`
gives every call that is owed a tuple one, at that call's own closing paren, so
nested calls, calls side by side, and a nested call to a non-variadic wrapper
each get exactly one `, .{}`; the local, field, string and comment decisions are
unchanged. **Its allocation invariant:** a declaration rewritten only for a
routed data object, and a declaration making a single variadic call, allocate
nothing here. One outstanding close is held in one optional index, as before; the
arena stack is appended to only when a second call is discovered while the first
has not closed. Any two closes pending together are strictly nested — balanced
parentheses are either nested or disjoint, and a disjoint later call is reached
only after the earlier one has closed — so the innermost close is always on top,
and no nesting depth is assumed or capped. Separately, `runtime/loader.zig`
discarded `Config.validate`'s refusal text, so a provider failing the
post-resolution check returned `ValidationFailed` and said nothing about why; it
now prints the refusal, as the other copies of that core do, with the load's
closed-failure, readiness and no-reset semantics unchanged.
`runtime/graph.zig`'s `provider_excluded` comment said the list keeps
declarations direct; `--exclude` routes to `optional` (`generate.zig`,
`Options.routeOf`), and only `libc_noise` keeps a declaration direct, so the
comment says that instead. No route policy changed.

**Status: partly observed.** The driver ran
both scratch inputs through the real generator and compiled a real generated
consumer that loaded an actual shared C provider, which covered the dispatch
root and one working shape of the tuple repair
(`local://foundation-resumed-core-root-actual-loaded-run-after.json`,
`local://foundation-resumed-core-varargs-actual-loaded-run-after.json`). That was
the revision that marked every outstanding close in a token-indexed table, which
cost one byte per token for every rewritten declaration. **The
single-index-plus-stack revision above is the one still unobserved by a targeted
repro.** Its first form
truncated the stack before reading the close it was about to return, so the real
generator aborted with SIGABRT-6 on an index one past the new length
(`local://foundation-resumed-core-varargs-stack-revision-repro.json`). The
repaired form reads the innermost close before truncating, and **it has now
run**: the eight `-Druntime=true` cells of epoch `20261004T232823091897Z-23133`
execute the real generator over this tree's own translated header in every cell —
each cell's receipt names the `blake3-runtime-generate-…` executable it ran — and
the dispatch it wrote compiled and answered all six published-vector tests in
each, across four optimize modes and both linkages, with the facade reaching a
provider through the loader. The 53-target cohort of `20261004T221720228710Z-45046`
builds the same graph without `-Druntime` and never runs the generator.

What that does not reach is unchanged. A nested variadic call inside another one
— the shape the scratch input exists for — occurs nowhere in this header, so the
tuple repair itself is still exercised only by the two scratch runs named above.
What the SDK graph adds is the rest of the generator: a dispatch that compiles
*and* answers six published vectors under four optimize modes and both linkages,
which neither scratch run did.

The loader print is on the refusal path and no run above
refused a provider; the `graph.zig` change is a comment. Neither is exercised.