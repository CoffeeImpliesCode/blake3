# blake3 — the BLAKE3 C library, built and wrapped in Zig

This package compiles BLAKE3 **1.8.7** — upstream's own C, byte for byte, from
the `c/` directory in this repository — and publishes a small, allocation-free
Zig facade over the translated `blake3.h`. No part of the hash function is
reimplemented, nothing is downloaded at build time, and there is no dependency
of any kind in `build.zig.zon`.

Upstream: `https://github.com/BLAKE3-team/BLAKE3`, tag `1.8.7`, commit
`f3149ec5bb5449af877ba20377a11008ff499fa2`. Provenance, licences and the
integrity record are in [`UPSTREAM.md`](UPSTREAM.md), [`NOTICE.md`](NOTICE.md)
and [`UPSTREAM.sha256`](UPSTREAM.sha256).

This package is local, uncommitted and unpublished: these files are not
committed, nothing has been published, and no publication is authorized in this
expansion.

## Requirements

Zig **0.16.0** — the real compiler, not the bare `zig` on `PATH`, which in
this workspace is a version dispatcher; through the dispatcher the command is
`zig 0.16.0 build`. Plus a C compiler and libc, both of which Zig supplies.
Nothing is fetched.

## Commands

| Command | What it does |
|---|---|
| `zig build` | compiles the C library, installs `libblake3.a` and `blake3.h` into `zig-out/`, and compiles the example |
| `zig build test` | runs `tests.zig`, which replays upstream's published vectors |
| `zig build test -Doptimize=ReleaseSafe` | the same tests with the optimizer on |
| `zig build test -Dportable=true` | the same tests against the scalar core alone |
| `zig build smoke` | runs `smoke.zig`, which checks its answers and exits non-zero on any mismatch |
| `zig build smoke -Dportable=true` | the example against the scalar core alone |
| `zig build check -Dtarget=<triple>` | compiles the C core, the facade, the tests and the example for one target, running nothing |
| `cd consumer && zig build run` | the same library, consumed by a package that did not write it |

Add `-j8 --summary all`, and `--cache-dir <dir>`, as your workspace does.

The six cross-target checks, one command each, no target skipped:

```
zig build check -Dtarget=x86_64-linux-gnu  -j8 --summary all --cache-dir /home/tmp/gertullj/foundation-libs-cache/blake3/x86_64-linux-gnu
zig build check -Dtarget=aarch64-linux-gnu -j8 --summary all --cache-dir /home/tmp/gertullj/foundation-libs-cache/blake3/aarch64-linux-gnu
zig build check -Dtarget=aarch64-macos-none -j8 --summary all --cache-dir /home/tmp/gertullj/foundation-libs-cache/blake3/aarch64-macos-none
zig build check -Dtarget=x86_64-windows-gnu -j8 --summary all --cache-dir /home/tmp/gertullj/foundation-libs-cache/blake3/x86_64-windows-gnu
zig build check -Dtarget=riscv64-linux-gnu -j8 --summary all --cache-dir /home/tmp/gertullj/foundation-libs-cache/blake3/riscv64-linux-gnu
zig build check -Dtarget=wasm32-wasi -j8 --summary all --cache-dir /home/tmp/gertullj/foundation-libs-cache/blake3/wasm32-wasi
```

`zig build check` with no `-Dtarget` walks all six in one graph.

### The full platform matrix

The six targets above are a compile-only gate that runs nothing. The gate that
runs this package's own Zig tests on every platform in Zig 0.16.0's published
Tier 1/2 table — 53 of them, including the 32-bit and big-endian ones the
six-target list does not reach — is `cross-test`, run from the package root:

```
cross-test
```

`cross-test` discovers `cross-test.profile.sh` in this directory on its own.
That profile is settings only: it names the standard `test` step and nothing
else. No target list, no `-Dtarget`, no `-Doptimize`, no artifact hooks, no host
path. For each platform the harness runs `zig build test -Dtarget=TARGET` over
the same graph and the same `tests.zig` any other `-Dtarget` produces, executes
the resulting binary where a native or emulator runner exists, and records
explicit `build_only` coverage — compiled, not executed — where none does.
`build_only` is never counted as a pass, and the six-target `check` matrix above
is not a substitute for this: it produces no test result at all.

It has been run, twice. The first full matrix compiled all 53 targets and then
failed two of them on a deadline rather than on an answer; the corrected matrix
(`run_id=20261002-055258-61044-19309`, 2026-10-02) built all 53 with exit 0 and
**executed this package's six tests on 20 of them — 6/6 each, zero failures**.
The other 33 are `build_only`: compiled, not executed, because this host has no
native, emulated or emulating runner for them, which is a compile result and
never a test pass.

The 20 that ran are `x86_64-linux`, `aarch64-linux`, `aarch64_be-linux`,
`arm-linux`, `armeb-linux`, `hexagon-linux`, `loongarch64-linux`, `mips-linux`,
`mipsel-linux`, `mips64-linux`, `mips64el-linux`, `powerpc-linux`,
`powerpc64-linux`, `powerpc64le-linux`, `riscv32-linux`, `riscv64-linux`,
`s390x-linux`, `thumb-linux`, `thumbeb-linux` and `x86-linux`.
`local://foundation-cross-test-corrected-blake3.json` carries the per-target
record (build exit, run exit, test count, reason, and the exact
`zig build test -Dtarget=… --test-timeout 1800s` command per target);
`local://foundation-cross-test-corrected-blake3-<target>.log` is that target's
own build summary.

The profile's deadlines are now `CROSS_BUILD_TIMEOUT=3600` for one target's
compile plus complete run and `CROSS_TIMEOUT=1800` for one test case. Same
Debug graph, same six tests, same vectors: they were raised because the first
matrix, at the harness's 300-second per-test default, timed out two AArch64
rows under QEMU — `aarch64-linux`'s streaming test after `5m368.911ms`, and
`aarch64_be-linux`'s one-shot and streaming tests after `5m248.837ms` and
`5m112.063ms`, with `5/6` and `4/6` tests passing beside them
(`local://foundation-cross-test-matrix-blake3-aarch64-linux.log`,
`…-matrix-blake3-aarch64_be-linux.log`, both exit 1). With 1800 seconds both
rows report `run test blake3-tests 6 pass (6 total) 1m`. No test was shortened,
dropped or re-pinned to get there.

`cross-test --list` and `cross-test --no-profile --list` name the same 53
targets when run from this directory, so the profile narrows the matrix to
nothing (`local://foundation-cross-test-profile-blake3-list_profile.log`,
`…-list_no_profile.log`, both exit 0); `bash -n` on the profile is exit 0
(`…-profile-blake3-syntax.log`).

## Using it

In your `build.zig.zon`:

```zig
.dependencies = .{
    .blake3 = .{ .path = "../blake3" },
},
```

In your `build.zig`:

```zig
const dep = b.dependency("blake3", .{ .target = target, .optimize = optimize });
exe_mod.addImport("blake3", dep.module("blake3"));
```

Then:

```zig
const blake3 = @import("blake3");

var digest: blake3.Out = undefined;       // 32 bytes: the default digest
blake3.hash("hello", &digest);

// Streaming instead: where the input is split does not change the digest.
var hasher = blake3.init();
blake3.update(&hasher, "hel");
blake3.update(&hasher, "lo");

// More than 32 bytes is the same hash read further along its output stream.
var extended: [64]u8 = undefined;         // bytes 32..96 of that stream
blake3.finalizeSeek(&hasher, 32, &extended);
```

`consumer/` is exactly this, in working form.

## The API

Constants, read out of `c/blake3.h`: `out_len` (32), `key_len` (32),
`block_len` (64), `chunk_len` (1024), plus the types `Out`, `Key` and
`Hasher` (`Hasher` is upstream's `blake3_hasher`, unchanged).

| Operation | What it does |
|---|---|
| `init()` | a hasher in ordinary unkeyed mode |
| `initKeyed(key)` | keyed mode — a PRF and a MAC. `Key` is `[32]u8`, so the length is the type |
| `initDeriveKey(context)` | key-derivation mode. The context is passed **by length**, not as a C string, so an embedded NUL is a different context instead of a truncation |
| `update(hasher, input)` | absorb more input; the split points do not matter |
| `finalize(&hasher, out)` | write `out.len` bytes of output; leaves the hasher unchanged |
| `finalizeSeek(&hasher, seek, out)` | the same output stream read from byte `seek` |
| `reset(hasher)` | back to the initial state, **keeping the mode** — a keyed hasher stays keyed |
| `hash`, `hashKeyed`, `deriveKey` | one-shot forms of the three modes |
| `pub const c` | the raw translated header, for anything the facade does not name |

**Lifetime.** Nothing here allocates and nothing needs freeing. Upstream
allocates nothing, so buffers go in and bytes come out and the caller owns all
of them. A `Hasher` is returned by value or borrowed through a pointer; it is
plain mutable state with no locking, so it belongs to one thread at a time.
`finalize` takes `*const Hasher` because upstream finalizes through
`const blake3_hasher *`: finalizing does not disturb the state, and a caller may
finalize the same hasher as often and at as many lengths as it likes.

**Bounds.** There is nothing to check at run time, which is why there is no
error union: the key length is an array type, the output length is the length of
the caller's own slice, and the context length is passed explicitly. The facade
writes exactly `out.len` bytes and nothing outside it, a zero-length `out` writes
nothing (upstream checks for that itself before touching the pointer), and an
empty `update` is a no-op. Every public contract here is enforced by ordinary
types and ordinary comparisons that survive an optimized build; no
`std.debug.assert` guards anything a caller can reach.

**Errors.** None, and that is upstream's shape rather than an omission: every
entry point in `c/blake3.h:63-80` is `void` and none of them can fail. Inventing
an error union would mean reporting conditions that cannot occur.

## Build modes

* **Default (bundled).** Compiles `c/blake3.c`, `c/blake3_dispatch.c` and
  `c/blake3_portable.c` from this repository, for the target the caller asked
  for, and adds the SIMD kernels that architecture has:

  * x86 and x86_64: the four C intrinsics kernels (`c/blake3_sse2.c`,
    `c/blake3_sse41.c`, `c/blake3_avx2.c`, `c/blake3_avx512.c`), **each one an
    object of its own**, compiled against a target taken from the caller's and
    then pinned to the baseline CPU model with exactly that row's instruction
    set switched on and nothing else.
  * AArch64: `c/blake3_neon.c`, with `-DBLAKE3_USE_NEON=1`. No per-kernel
    target is needed, because NEON is baseline for AArch64.
  * riscv64 and wasm32: no kernel. The portable core is upstream's documented
    answer (`c/README.md:376-383`).

  The core sources and `c/blake3_dispatch.c` keep the caller's requested
  baseline, which is what keeps the run-time CPUID dispatch in
  `c/blake3_dispatch.c:168-300` worth reading: the dispatcher chooses a kernel
  the CPU reports having, and no kernel object contains instructions beyond its
  own instruction set, so a dispatcher answer is never a promise the code
  cannot keep. Nothing raises the whole library's CPU to make a kernel
  compile (`FORK-NOTES.md` §9 has the failure that rule answers).

  Upstream's hand-written x86_64 assembly is not compiled: it would need a
  different source file per platform and a working assembler for each matrix
  target, and it implements the same five instruction sets that
  `c/blake3_dispatch.c` dispatches over at run time. oneTBB stays off, as
  upstream's default.
* **`-Dportable=true`.** The scalar core only, for any target: the same facade,
  the same fixture, upstream's `BLAKE3_NO_*` macros, no SIMD kernel. It exists
  so the published vectors can be gated twice — once through the dispatched
  kernels and once through `blake3_portable.c` alone — because a disagreement
  between those two paths is a real defect class, not a difference in the tests.
  It has no effect in system mode, where no C is compiled here.
* **`-Dsystem=true`, or `-fsys=blake3` on a runner that supplies the map.**
  Links an installed `libblake3` and translates **the installed `blake3.h`**
  instead of the bundled one, so the declarations describe the library actually
  on disk rather than one that may not be (`WISDOM.md` W14). Nothing is compiled
  from this tree in that mode, so nothing is installed by it either. This mode
  needs an installed library with its own header; **it has not been gated in this
  workspace and no run of it is claimed here.**

## Verification status

The authoritative table. Every build row was run in this workspace with `-j8` and
`--summary all`, each against its own `--cache-dir` on an approved scratch
mount; the receipt named in the row holds the output and the exit code. The
packaging rows ran outside this working tree, from an approved external scratch
build root, and each names the command that was run there. Nothing in it is
predicted, and no row is inherited from a row that ran earlier: each is its own
observation with its own receipt, and a row says so when it was observed on an
earlier date than its neighbours. Two rows are deliberately **not run** and say
so; neither of them is a gate this tree has yet answered.

| Gate | Command | Observed | Receipt |
|---|---|---|---|
| install, `test` (Debug) and `smoke` (Debug) | `zig build test smoke install -Doptimize=Debug -j8 --summary all` | exit 0, 19/19 steps; 6/6 tests; `smoke` printed every published digest and closed on `every digest matched the published vectors` | `local://foundation-cross-test-stable-blake3-native-Debug.log` |
| `test` (ReleaseSafe) and `smoke` (ReleaseSafe) | `zig build test smoke -Doptimize=ReleaseSafe -j8 --summary all` | exit 0, 17/17 steps; 6/6 tests; same published digests | `local://foundation-cross-test-stable-blake3-native-ReleaseSafe.log` |
| consumer, against this source tree | `cd consumer && zig build run -j8 --summary all` | exit 0, 14/14 steps; it printed `blake3 consumer`, `linked C library reports version 1.8.7`, the published digests and `every digest matched the published vectors`. `consumer/build.zig.zon` depends on `.blake3 = .{ .path = ".." }`, so this resolves the module out of this source tree, not out of a fetched copy | `local://foundation-cross-test-stable-blake3-native-consumer.log` |
| `test` (scalar core) | `zig build test -Dportable=true` | exit 0, 6/6 tests. Observed 2026-10-01; not re-run in the 2026-10-02 native round, so the row does not cover the current `build.zig` | `local://foundation-expansion-blake3-isa-portable-debug-130.log` |
| `smoke` (scalar core) | `zig build smoke -Dportable=true` | exit 0, every digest matched. Observed 2026-10-01; not re-run in the 2026-10-02 native round | `local://foundation-expansion-blake3-isa-portable-smoke-131.log` |
| `check` x86_64-linux-gnu | `zig build check -Dtarget=x86_64-linux-gnu -Doptimize=Debug -j8 --summary all` | exit 0, 14/14 steps, all four kernel objects compiled | `local://foundation-cross-test-baseline-blake3-x86_64-linux-gnu.log` |
| `check` x86_64-windows-gnu | `zig build check -Dtarget=x86_64-windows-gnu -Doptimize=Debug -j8 --summary all` | exit 0, 14/14 steps, all four kernel objects | `local://foundation-cross-test-baseline-blake3-x86_64-windows-gnu.log` |
| `check` aarch64-linux-gnu | `zig build check -Dtarget=aarch64-linux-gnu -Doptimize=Debug -j8 --summary all` | exit 0, 6/6 steps | `local://foundation-cross-test-baseline-blake3-aarch64-linux-gnu.log` |
| `check` aarch64-macos-none | `zig build check -Dtarget=aarch64-macos-none -Doptimize=Debug -j8 --summary all` | exit 0, 6/6 steps | `local://foundation-cross-test-baseline-blake3-aarch64-macos-none.log` |
| `check` riscv64-linux-gnu | `zig build check -Dtarget=riscv64-linux-gnu -Doptimize=Debug -j8 --summary all` | exit 0, 6/6 steps | `local://foundation-cross-test-baseline-blake3-riscv64-linux-gnu.log` |
| `check` wasm32-wasi | `zig build check -Dtarget=wasm32-wasi -Doptimize=Debug -j8 --summary all` | exit 0, 6/6 steps | `local://foundation-cross-test-baseline-blake3-wasm32-wasi.log` |
| integrity | `sha256sum -c UPSTREAM.sha256` | exit 0, 52 records, no failures | `local://foundation-expansion-blake3-immutable-integrity-80.log` |
| pristine upstream bytes | `git diff --exit-code f3149ec5… -- c test_vectors LICENSE_A2 LICENSE_A2LLVM LICENSE_CC0 README.md` | exit 0, no output: the shipped upstream files equal the pinned commit. A direct diff of this working tree against the pinned commit — not a replay of `git archive`, and not a CI run | `local://foundation-expansion-blake3-pristine-source-81.log` |
| installed C surface | `zig build --prefix <scratch outside the tree>`, then `zig cc` of a C program against the installed `blake3.h` and `libblake3.a`, then run it | install exit 0; the program printed `public C surface compiled, linked and ran` and exited 0 | `local://foundation-expansion-blake3-installed-artifact-gruenau8-187.log`, `local://foundation-expansion-blake3-installed-C-surface-190.log` |
| `zig fetch` (packaged copy) — **historical** | `zig fetch --global-cache-dir <scratch>/packages <this package directory>`, run from an external approved scratch build root | exit 0; it printed the package identity `blake3-1.8.7-V1p9dYNCFgANxaiTyV6hzK0BJYW2PtTiCwoUVZ3CtZBz`. Taken 2026-10-01T23:47Z, before `cross-test.profile.sh` joined `.paths`, so it records that `.paths`, not the current one | `local://foundation-expansion-blake3-external-driver-package-fetch-315.log` |
| integrity, **inside the fetched package** — **historical** | `sha256sum -c UPSTREAM.sha256`, run in the materialised copy | exit 0, 52 records, every line `<path>: OK`, nothing failed. Same fetch, so same date | `local://foundation-expansion-blake3-materialized-package-integrity-329.log` |
| consumer, **inside the fetched package** — **historical** | `zig build run -j8 --cache-dir <scratch> --global-cache-dir <zig cache>`, run in the materialised copy's `consumer/` | exit 0; it printed `blake3 consumer`, `linked C library reports version 1.8.7`, the published digests, and `every digest matched the published vectors`. Same fetch, so same date | `local://foundation-expansion-blake3-materialized-package-consumer-330.log` |
| **package after the cross-test profile** | final filtered `zig fetch`, source/fetched integrity, and the fetched consumer after SDK documents settle | **Driver-owned closure proof.** The final result and package identity are recorded in the workspace ledger's `cross_test_wave.materialized_packages.blake3`; the historical rows above predate the profile and deadline changes. Package identities are kept outside the package whose documentation contributes to them | `local://foundation-cross-test-package-regression.json` |
| `-Dsystem=true` | — | **not run.** This workspace has no installed `libblake3`, so there is no receipt and no claim in either direction | — |
| `cross-test`, full platform matrix | `cross-test --jobs 2 --build-jobs 4 --build-timeout 3600` from the package root, using `cross-test.profile.sh` | run exit 0 (`20261002-055258-61044-19309`): **all 53 targets built, 20 executed the six tests 6/6 each, 33 `build_only`, 0 failed.** The 33 are compiled-not-run, never counted as test passes. Every target's build exit, run exit, test count, reason and exact `zig build test` command is in the JSON, and each target has its own log | `local://foundation-cross-test-corrected-blake3.json`, per-target `local://foundation-cross-test-corrected-blake3-<target>.log` |

What the table does and does not say:

* **The six cross-target rows are compile evidence and nothing more.** `zig
  build check` builds the C core, the translated header, the facade, `tests.zig`
  and the example for that target and runs nothing: no foreign binary was
  executed for any of them, and none of them claims one was. Six steps, six
  targets, none skipped and none pre-judged.
* **The native rows ran on one host, and no row claims which kernel it chose.**
  `6/6 tests` is what this build produced on the machine that ran it. No gate
  prints which instruction set the run-time dispatch selected, so none is
  named here. `-Dportable=true` is the row that holds the scalar core to the
  same published answers, which is why it is a gate of its own rather than a
  variation.
* **No row compares this build against itself.** The version the linked library
  reports is printed by `smoke` (`1.8.7`, read out of `c/blake3.h:33`) and
  nothing compares it to a constant; every digest checked anywhere comes from
  upstream's published vectors.
* **Which tree each row compiled.** The three native rows, the six `check` rows
  and the matrix row are 2026-10-02 observations of this tree. The two
  `-Dportable=true` rows and the installed C-surface row are 2026-10-01
  observations; since then `build.zig`'s only edit is the module doc comment
  (`CHANGELOG.md` entry 14) and `build.zig.zon` gained one line naming the
  cross-test profile. No C source, header, fixture, test, example or licence
  text has changed, which is what the integrity and pristine-bytes rows cover —
  they are still the 52 records of exactly the bytes every 2026-10-02 row
  compiled. The six tests every test row counted are the six `tests.zig` holds.
* **The matrix row is the only row that runs this package's own test binary.**
  Twenty platforms executed it; the other 33 compiled and were skipped for want
  of a runner. `x86-linux` is worth naming: 32-bit x86 took all four intrinsics
  kernels, AVX-512 included, and still produced 6/6 — upstream's own recipe, now
  observed rather than argued (`FORK-NOTES.md` §12).
* **The three packaging rows ran against a copy, not against this tree — and
  that copy predates the cross-test profile.** The driver ran `zig fetch` over
  this package directory from an external approved scratch build root; what
  landed in the package cache is a filtered copy of exactly what
  `build.zig.zon`'s `.paths` listed on 2026-10-01. The next two rows were run
  **inside that copy**: the 52-record `UPSTREAM.sha256` check, and `consumer/`
  building the fetched library and printing the published vectors. So `.paths`
  was not only an assertion about what a dependent would receive — the record's
  files were all present in a copy that was actually received, and a package
  that did not write this one built and ran against it. What that copy did not
  contain is `cross-test.profile.sh`, which `.paths` has carried since, so those
  three rows are kept as history and the row after them stays pending until a
  fetch of the current tree is run.
* **What those rows do not establish.** Nothing was published and nothing was
  resolved from a registry: the fetch source was this local directory, so no
  remote URL, no registry index and no published `.hash` was exercised, and no
  publication is authorized. The fetched copy is not a Git clone either, so the
  pristine-bytes row is a separate observation about this working tree and not
  something the fetched copy restates.
* **Absence of a run is not a result.** `-Dsystem=true` has no receipt here.
  That says nothing about whether the mode works; `FORK-NOTES.md` §6 records
  what it would take.

## Testing approach

The primary fixture is upstream's own `test_vectors/test_vectors.json`, embedded
with `@embedFile`. It carries an input length and three outputs per case — one
per mode — each a complete 131-byte extended output, for 35 inputs from 0 to
102400 bytes that cross block and chunk boundaries; the inputs themselves are
the repeating 251-byte pattern the file's own `_comment` describes, and the
answers come from the file rather than from running the library. `smoke.zig`
quotes the same published answers for the two smallest cases and exits non-zero
on any disagreement, so its exit code is the check. The installed C-surface gate
holds the same answers in C, compiled against the installed header and linked
against the installed archive, so the Zig facade is not the only thing standing
between the vectors and a wrong digest. A same-code round trip is not what any
of this rests on.

## Integrity

```
sha256sum -c UPSTREAM.sha256
```

52 records covering every upstream file this package ships — the whole `c/`
directory, the fixture, the three licence texts and upstream's README — and
nothing else, so the same command works in a clone and in an unpacked package.
Both halves of that claim have been run here: `sha256sum -c UPSTREAM.sha256`
reported 52 records and no failures, and `git diff --exit-code` against the
pinned commit over `c`, `test_vectors`, the three licence texts and `README.md`
produced no output, so the bytes this package ships are the bytes of commit
`f3149ec5bb5449af877ba20377a11008ff499fa2`. See [`UPSTREAM.md`](UPSTREAM.md)
for how the digests were produced, and what the record does and does not prove
on its own.

The record has also been checked where a dependent actually finds it: run
**inside the package `zig fetch` materialised from this directory**, it reported
the same 52 records, every line `OK`, with nothing missing
(`…-materialized-package-integrity-329.log`). So every file the record names is
one `build.zig.zon`'s `.paths` delivered — the record is complete against the
package, not only against this working tree. That fetch was taken before
`cross-test.profile.sh` joined `.paths`, so it is kept as history and the same
check inside a fetch of the current tree is still to be run. And it is a local
fetch of a local directory: it says nothing about publication or about
resolution from a registry, neither of which has been tested.

## Licence

Upstream is `CC0-1.0 OR Apache-2.0 OR Apache-2.0 WITH LLVM-exception`; all three
texts ship verbatim as `LICENSE_CC0`, `LICENSE_A2` and `LICENSE_A2LLVM`, and
this fork narrows none of that and re-grants none of it. This fork's own files
carry no licence statement in this repository, and that is recorded rather than
answered: an earlier revision of this README offered them under Apache-2.0
because that text happens to ship here, which is a grant nobody has authority
to make for them. Attribution, the files this fork adds or edits, and the
patent-grant termination clause are in [`NOTICE.md`](NOTICE.md).

BLAKE3 is **not** a password hashing algorithm (`README.md:80-83`); the keyed
mode is a fast MAC, and upstream recommends Argon2 for passwords.
