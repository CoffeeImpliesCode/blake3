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
belongs in `NOTICE.md` when it is made.

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
