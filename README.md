# BLAKE3, built and packaged for Zig 0.16

This repository is a Zig 0.16 SDK around **BLAKE3 1.8.7**, the upstream C hash
library. It compiles upstream's own C sources from `c/`, publishes an
allocation-free Zig facade over the translated `blake3.h`, installs the native
library and header, and packages the same source through Nix and devenv.

Upstream is `https://github.com/BLAKE3-team/BLAKE3`, tag `1.8.7`, commit
`f3149ec5bb5449af877ba20377a11008ff499fa2`.

| Document | What it is |
|---|---|
| [`README.zig.md`](README.zig.md) | the interface documentation: commands, routes, the API and its contracts, and the verification table |
| [`README.upstream.md`](README.upstream.md) | upstream's own README, preserved byte for byte — what upstream says |
| [`UPSTREAM.md`](UPSTREAM.md) | the pin, the import mechanism, and what the integrity record does and does not prove |
| [`NOTICE.md`](NOTICE.md) | attribution, the licence inventory, and every file this fork adds or edits |
| [`FORK-LICENSE.md`](FORK-LICENSE.md) | the licence of this fork's own files and the authorization behind it |
| [`FORK-NOTES.md`](FORK-NOTES.md) | the problems met while doing this, and what they forced |
| [`CHANGELOG.md`](CHANGELOG.md) | numbered fork-only divergences |
| [`UPSTREAM.sha256`](UPSTREAM.sha256) | SHA-256 of every upstream file this package ships |

---

## Current native-source deviations

**None.** No upstream C source, header, assembly kernel, example, test harness,
fixture or licence text is modified. `UPSTREAM.sha256` records the SHA-256 of
every upstream file the package ships, and the only upstream file this fork edits
at all is `.gitignore`, by appending, which is why that one file is excluded from
the record and documented in `NOTICE.md` instead.

The hash function, its SIMD kernels, its run-time CPU dispatch and its published
test vectors are upstream's own bytes.

---

## Current native-build deviations

These are deviations of the **build** from what upstream's own CMake build does.
Each is deliberate and each is recorded with its reason in `FORK-NOTES.md`; the
numbered history of how each one arrived, with its receipts where any exist, is
in [`CHANGELOG.md`](CHANGELOG.md), whose entries name the entry number beside
each deviation below.

| # | Deviation | Why |
|---|---|---|
| 1 | **No CMake, no autotools, no Make.** `build.zig` compiles the library itself (`CHANGELOG.md` §1). | No build-time download, no system-installed default, and a dependent gets upstream's tree rather than a configured subset. Upstream's `c/CMakeLists.txt`, `c/CMakePresets.json` and `c/Makefile.testing` ship untouched and are read by nothing. |
| 2 | **The x86 C intrinsics kernels, not upstream's hand-written assembly** (`CHANGELOG.md` §2). The four `c/blake3_sse2.c`, `c/blake3_sse41.c`, `c/blake3_avx2.c`, `c/blake3_avx512.c` kernels are compiled; the `.S`/`.asm` files are not. | Both flavours implement the same five instruction sets, and they cannot be mixed: each defines the same `blake3_compress_in_place_*` symbols. The assembly route needs a different source file per platform and a working assembler for every matrix target. |
| 3 | **Each SIMD kernel is its own object, compiled for its own instruction set alone** (`CHANGELOG.md` §10). The core and `c/blake3_dispatch.c` stay at the target baseline. | A kernel object that also contained baseline-plus-extra instructions would make a CPUID dispatch answer a promise the code cannot keep. Adding the kernels to the library's own C module instead of private per-kernel modules is what `FORK-NOTES.md` §9 records as the failure this rule answers. |
| 4 | **C standard pinned to `-std=gnu11` on every translation unit** (`CHANGELOG.md` §2). Upstream asks for C99 with extensions off. | `c/blake3_dispatch.c` takes its C11 atomics path wherever `<stdatomic.h>` exists, and pinning the level keeps `_Atomic int g_cpu_features` on its native spelling rather than on a compiler extension. |
| 5 | **`-Dlinkage=static\|dynamic` selects static or shared delivery** (`CHANGELOG.md` §21). Static remains the default. | The default is what this SDK has always produced, so no existing consumer's linkage changes. `-Druntime` is a separate, consumer-side option and is orthogonal. |
| 6 | **The example program is compiled, not installed.** | It is a compile proof that the facade, the translated header and the library agree; it is not a deliverable. |
| 7 | **`b3sum` and the Rust crate are not built.** `Cargo.toml`, `src/`, `b3sum/`, `benches/`, `reference_impl/`, `tools/`, `media/` ship in the repository for provenance only. | Nothing in the package references them, and this SDK is the C library with a Zig facade. They are not in the package a dependent receives. |
| 8 | **`devenv` is the canonical development shell** (`CHANGELOG.md` §19). `nix develop` exists in `flake.nix` as a convenience and is not the documented path. | Entering a dev shell must not require building the SDK, so the shell carries tools and explicit tasks only. |
| 9 | **`-fvisibility=hidden` reaches the shared delivery only** (`CHANGELOG.md` §21, `FORK-NOTES.md` §19). Upstream's static archive carries the flag; this one does not. | Visibility governs a dynamic symbol table and an archive has none, so the flag is inert for a static archive. `static` is the delivery every gate in this repository's recorded history observed, and perturbing that command line for an inert property is the worse trade. The artifact that actually has an export surface — the shared object — matches upstream exactly, and the export set comes from upstream's own `BLAKE3_API` rather than from any version script or hand-written list |

---

## Build / run / test matrix

Two different things are in this table and they must not be merged:

* **Historical rows** are observations the driver recorded on the dates named,
  with the receipt named. They describe the tree as it stood on that date.
* **The second table** carries the gates this migration owes. It is no longer
  wholly unverified: the source-bound cohorts below have closed several of those
  rows against this tree, and each closed row names the epoch that closed it and
  what that epoch actually observed. A row still marked `PENDING-VERIFICATION`
  has landed and no gate has looked at it: it is not a result, and none may be
  reported as one.

A green matrix is not a green suite. `build_only` is compiled-but-not-run and is
never a pass: the current 53-target cohort built all 53 targets and executed this
package's six tests on 20 of them.

### Historical observations (recorded before this migration)

| Gate | Command | Observed | Receipt |
|---|---|---|---|
| install, `test` (Debug), `smoke` (Debug) | `zig build test smoke install -Doptimize=Debug -j8 --summary all` | exit 0, 19/19 steps, 6/6 tests, smoke printed every published digest | `local://foundation-cross-test-stable-blake3-native-Debug.log` |
| `test` + `smoke` (ReleaseSafe) | `zig build test smoke -Doptimize=ReleaseSafe -j8 --summary all` | exit 0, 17/17 steps, 6/6 tests | `local://foundation-cross-test-stable-blake3-native-ReleaseSafe.log` |
| separate consumer package | `cd consumer && zig build run` | exit 0, 14/14 steps; printed the published digests | `local://foundation-cross-test-stable-blake3-native-consumer.log` |
| scalar-core `test` — **2026-10-01** | `zig build test -Dportable=true` | exit 0, 6/6 | `local://foundation-expansion-blake3-isa-portable-debug-130.log` |
| scalar-core `smoke` — **2026-10-01** | `zig build smoke -Dportable=true` | exit 0 | `local://foundation-expansion-blake3-isa-portable-smoke-131.log` |
| installed C surface — **2026-10-01** | `zig build --prefix <scratch>`, then `zig cc` of a C program against the installed header and archive, then run it | exit 0; printed `public C surface compiled, linked and ran` | `local://foundation-expansion-blake3-installed-artifact-gruenau8-187.log`, `…-installed-C-surface-190.log` |
| six-target compile-only `check` matrix — **2026-10-02** | `zig build check -Dtarget=<triple>` for `x86_64-linux-gnu`, `aarch64-linux-gnu`, `aarch64-macos-none`, `x86_64-windows-gnu`, `riscv64-linux-gnu`, `wasm32-wasi` | exit 0 on all six. Compile evidence only: no foreign binary was executed for any of them | `local://foundation-cross-test-baseline-blake3-<target>.log` |
| full platform matrix — **2026-10-02** | `cross-test --jobs 2 --build-jobs 4 --build-timeout 3600` | run exit 0: **all 53 targets built, 20 executed the six tests 6/6 each, 33 `build_only`, 0 failed.** `build_only` is compiled-not-run and is never a test pass | `local://foundation-cross-test-corrected-blake3.json` plus a per-target log |
| integrity | `sha256sum -c UPSTREAM.sha256` | exit 0, 52 records, no failures | `local://foundation-expansion-blake3-immutable-integrity-80.log` |
| pristine upstream bytes | `git diff --exit-code f3149ec5… -- c test_vectors LICENSE_A2 LICENSE_A2LLVM LICENSE_CC0 README.md` — as run; see the note below for today's spelling | exit 0, no output | `local://foundation-expansion-blake3-pristine-source-81.log` |
| `zig fetch` of the package, integrity and consumer inside it — **2026-10-01** | run from an external scratch build root, then run inside the materialised copy | exit 0; 52 records `OK`, consumer printed the published digests. Taken before `cross-test.profile.sh` joined `.paths`, so it records that `.paths`, not the current one | `…-external-driver-package-fetch-315.log`, `…-materialized-package-integrity-329.log`, `…-materialized-package-consumer-330.log` |
| `-Dsystem=true` | — | **never run.** This workspace has no installed `libblake3`, so there is no receipt and no claim in either direction | — |


The `integrity` and `pristine upstream bytes` rows above named `README.md`,
because that was where upstream's README lived when they ran. The same checks
today name `README.upstream.md`; the bytes and the digest are unchanged, and
neither check has been re-run against the current tree.

### This migration, against the current source

Every gate this migration owes is still listed below. Each row carries either the
epoch that closed it and what that epoch actually observed, or
`PENDING-VERIFICATION`. The cohorts that closed rows here are:

* **Full 53-target matrix** — epoch `20261004T221720228710Z-45046`, receipt
  `blake3-53-target-8.json`: `cross-test --jobs 8 --build-jobs 8` from this
  package root.
* **Six-baseline compile-only** — epoch `20261005T014547Z-797a73f2`, one row,
  `baseline-blake3-check`: `zig build check -j8 --summary all` with no
  `-Dtarget`, so the graph's own whole-matrix step.
* **Native linked route, 8 cells** — epoch `20261004T233628757747Z-69351`, one
  receipt per cell, `blake3-native-final-<linkage>-<mode>.json`:
  `zig build test smoke install -Doptimize=<mode> -Dlinkage=<linkage>
  -Druntime=false`, four optimize modes times two linkages.
* **Runtime-loaded route, own provider, 8 cells** — epoch
  `20261004T232823091897Z-23133`, one receipt per cell,
  `blake3-loaded-final-<linkage>-<mode>.json`: the same command with
  `-Druntime=true` and `BLAKE3_TEST_PROVIDER` and `BLAKE3_TEST_ALIEN` exported by
  the driver, naming a provider this tree built.
* **Independent external provider probe** — wave `20261004T232439Z`, receipt
  `blake3-index.json`: this SDK's three declared external candidates, each tried
  by explicit `.path` and by explicit `.system`.

| Gate | Command to run | Status |
|---|---|---|
| linked static, all four optimize modes | `zig build test smoke install -Doptimize=<Debug\|ReleaseSafe\|ReleaseFast\|ReleaseSmall> -Dlinkage=static` | **OBSERVED — 4/4 cells**, `20261004T233628757747Z-69351`. Each cell: exit 0, 28/28 steps, 6/6 tests, `smoke success`, and a fresh prefix carrying `lib/libblake3.a`, `lib/pkgconfig/libblake3.pc`, `include/blake3.h` and the six licence and provenance files — 9 files. |
| linked shared, all four optimize modes | same, with `-Dlinkage=dynamic` | **OBSERVED — 4/4 cells**, same epoch. Each cell: exit 0, 28/28 steps, 6/6 tests, `smoke success`, and a prefix carrying `lib/libblake3.so`, `lib/libblake3.so.0`, `lib/libblake3.so.0.1.8`, `lib/pkgconfig/libblake3.pc`, `include/blake3.h` and the same six files — 11 files. |
| shared library exports and PIC-correct ISA objects | inspect the shared object's dynamic symbol table and its relocations | **PARTLY OBSERVED.** The object was produced and installed in all four modes, and the loader opened `libblake3.so.0.1.8` — the same file, by digest — and used it in all eight `-Druntime=true` cells of `20261004T232823091897Z-23133`, which shows its export surface carries every entry point this facade calls. **The inspection has not been run**: no receipt dumps a symbol table or relocations, so "each per-ISA kernel object is inside it, PIC-correct" stays source-confirmed. |
| full behavioural gate | `zig build test` and `zig build test -Doptimize=ReleaseSafe`, and `zig build test -Dportable=true` | **PARTLY OBSERVED.** Debug and ReleaseSafe are the two linked cells of `20261004T233628757747Z-69351`: 6/6 in each. `-Dportable=true` was in no cohort above; its last receipt is the 2026-10-01 row, which predates the current `build.zig`. |
| six-target compile-only matrix | `zig build check` for each of the six baselines | **OBSERVED, compile-only.** `20261005T014547Z-797a73f2`, `baseline-blake3-check`: exit 0, `failed: false`, 47/47 steps, all six triples at six steps each, no failing step line, no diagnostic. Its own expectation field carries `runtime_pass_claimed: false` and its `test_pass_lines` is empty, so no runtime result is hiding inside a green row. |
| full 53-target matrix | `cross-test` from the package root | **OBSERVED.** `20261004T221720228710Z-45046`, `blake3-53-target-8.json`: **53 targets — 20 runtime PASS (`reason: tests_complete`, six tests each), 33 `build_only` (`runtime_unavailable`), 0 fail, run exit 0**, `source_unchanged: true`, `jobs_honoured: true`. That is a green build of all 53 plus 20 executions, on the same twenty platforms as the 2026-10-02 row. It is not 53 test passes. |
| loader behavioural tests | `zig build -Dlinkage=dynamic --prefix <dir>`, export `BLAKE3_TEST_PROVIDER` and `BLAKE3_TEST_ALIEN`, then `zig build runtime-test -Druntime=true` — a failure that publishes nothing, a caller-driven retry, a second request for the provider already in use, many threads at one attempt | **PENDING-VERIFICATION.** Neither 8-cell wave asked for the `runtime-test` step — both ran `test smoke install` — so `runtime/load_tests.zig` and `runtime/core_tests.zig` have not been executed. |
| misuse control | `zig build runtime-misuse` — runs `after-load <provider>` and requires exit 0. **Control only**: `pre-load` and `linked-load` are compiled in every configuration but no build step runs them, because `Step.Run` has no "must not exit zero" check and writing down an unobserved exit code would be a fabricated gate | **PENDING-VERIFICATION.** `blake3-misuse` was compiled in all sixteen cells of the two 8-cell waves, and `runtime-misuse` was never among the steps those waves asked for, so `after-load` has not run. |
| misuse, driver-run only | run `runtime/misuse.zig pre-load` and `linked-load` directly, in **all four** optimize modes: each must stop, and the message must name the library, the function and the way out. No build step covers these — and this row is also the *only* way the pre-readiness panic gets observed in each mode, so the panic is unproven until it has been run here | **PENDING-VERIFICATION** — no cohort above ran either mode. |
| WASI boundary | `zig build check -Dtarget=wasm32-wasi -Dlinkage=dynamic` must report that the target has no dynamic linker and keep the static artifact, not fail obscurely | **PENDING-VERIFICATION.** `wasm32-wasi` was built by the 53-target cohort and by the baseline row, both at the default static linkage. `-Dlinkage=dynamic` on that target is still ungated, so nothing here says what the graph does with a dynamic delivery there. |
| typed and raw consumers | the separate `consumer/` package, plus a consumer using `blake3.c` directly | **PENDING-VERIFICATION.** No cohort above ran `consumer/`; all sixteen cells ran `test smoke install` from this package root. |
| installed C consumer | compile and run a C program against the installed `blake3.h` and native library, static **and** shared | **PENDING-VERIFICATION.** The install layout is recorded per cell, exactly as the file inventories in the two rows above name it, but no cohort compiled or ran a C program against an installed prefix. The last receipt is the 2026-10-01 row above, static only. |
| runtime-loaded consumer | own shared object and a compatible external provider, loaded by explicit path and by explicit system name | **Own shared object — OBSERVED:** `20261004T232823091897Z-23133`, 8/8 cells, four optimize modes times both linkages, `-Druntime=true`, `BLAKE3_TEST_PROVIDER` naming this tree's own `libblake3.so.0.1.8` and `BLAKE3_TEST_ALIEN` naming `/lib64/libm.so.6`; `tests.zig` calls `blake3.load` with that explicit path before its first test and every cell reports 6/6, with `smoke` run in each and `blake3-misuse` compiled in each. **Compatible external provider — NOT EXERCISED, a boundary and not a pass:** no independent external provider was accepted for this SDK; in `20261004T232439Z` every route carries `counts_as_external_coverage: false`, `external_successes_observed` is 0, the one successful route is `path-01-libblake3.so.0.1.8-success` with `independence: own`, and the three declared external candidates were the expected refusals across six routes by `.path` and by `.system`. Loading a library this tree did not build is unproved for BLAKE3. |
| runtime loader behaviour | startup, failure, explicit retry, idempotence, provider change, atomic publication, and the pre-readiness panic in every optimize mode including `ReleaseFast`/`ReleaseSmall` | **PENDING-VERIFICATION.** The eight loaded cells show that one load, by explicit path, reaches a real provider and that the published vectors survive it. What the contract is about *between* calls — a failure that publishes nothing, a caller-driven retry, a second request for the provider already in use, threads arriving at one attempt — lives in `runtime-test`, which has not been run; so does the pre-readiness panic per mode, which only `pre-load` reaches. |
| fetched filtered consumer | `zig fetch` this package, then build and run the consumer inside the materialised copy | **PENDING-VERIFICATION** — no cohort above fetched this package. |
| canonical devenv shell | `devenv shell`, and each declared task | **PENDING-VERIFICATION** — no cohort above entered a devenv shell or ran a task. |
| Nix static derivation | `nix build .#static`, then inspect the output layout and `nix-store --query --references` | **PENDING-VERIFICATION** — no derivation has been evaluated or built. |
| Nix shared derivation | `nix build .#shared`, same inspection | **PENDING-VERIFICATION** — same. |

Read together, the closed rows establish that this tree builds all 53 published
platforms, runs its six published-vector tests on 20 of them, builds and installs
both linkages in all four optimize modes, and reaches a real provider through the
loader in all eight runtime-loaded cells. They establish nothing about
`-Dsystem=true`, about an independent external provider, about the loader's
between-calls contract, about a Zig or C consumer built against an installed
prefix, or about either Nix derivation or the devenv shell. Those rows above still
read `PENDING-VERIFICATION`, and that is the current state of this tree, not a
summary of older ones.

---

## Consumption

### Requirements

Zig **0.16.0** — the real compiler, not a version-hiding shim on `PATH`. The
canonical way to obtain it is the devenv shell below. Plus a C compiler and libc,
both of which Zig supplies. Nothing is fetched at build time.

### From Zig

```zig
// build.zig.zon
.dependencies = .{ .blake3 = .{ .path = "../blake3" } },

// build.zig
const dep = b.dependency("blake3", .{ .target = target, .optimize = optimize });
exe_mod.addImport("blake3", dep.module("blake3"));
```

```zig
const blake3 = @import("blake3");

var digest: blake3.Out = undefined;                 // 32 bytes: the default digest
blake3.hash("hello", &digest);

var hasher = blake3.init();
blake3.update(&hasher, "hel");
blake3.update(&hasher, "lo");
blake3.finalize(&hasher, &digest);
```

The full interface — every route into the package, the API contracts for
lifetimes, buffers, state and bounds — is in [`README.zig.md`](README.zig.md).

### From C

`zig build install` writes the native library, the public header, the link
metadata and the carried licence material:

```
lib/libblake3.a                              (static, the default)
lib/pkgconfig/libblake3.pc
include/blake3.h
share/licenses/blake3/                       (LICENSE_A2, LICENSE_A2LLVM,
                                               LICENSE_CC0, NOTICE.md,
                                               FORK-LICENSE.md, UPSTREAM.md)
```

With `-Dlinkage=dynamic` the archive becomes a shared object instead: on ELF,
`libblake3.so.0.1.8` with the soname `libblake3.so.0` and a `libblake3.so`
symlink, reproducing upstream's `SOVERSION 0` (`c/CMakeLists.txt:150-155`); on
Darwin `libblake3.0.dylib`; on Windows `blake3.dll` plus `blake3.lib`. Nothing
about the installed header changes with linkage. `libblake3.pc` is the same
file in both variants, with `-DBLAKE3_DLL` added to `Cflags` for the shared one
exactly as upstream appends it under `BUILD_SHARED_LIBS`
(`c/CMakeLists.txt:139-145`).

`-Dlinkage` is **observed for delivery**, not for inspection. The 2026-10-04
native cohort built and installed the shared object in all four optimize modes,
naming exactly the three files above, and the loader opened `libblake3.so.0.1.8`
by explicit path in all eight `-Druntime=true` cells of the loaded cohort. The
symbol-table and relocation inspection the matrix above still owes has not been
run.

### Runtime loading

A consumer can build the facade against a library it names at run time instead
of one this tree links. That is a separate build configuration (`-Druntime`),
independent of `-Dlinkage`; under it nothing is linked into the module — neither
the archive this tree compiled nor an installed system library — and the consumer
calls an explicit load with an explicit source: an absolute file path, or a
basename handed to the platform loader unchanged. There is no path-to-system
fallback. The library is still built and installed, so a caller may equally name
the provider this tree did build.

The full contract, the required symbol set, the ABI prerequisites, the one
instance-per-binary sync-prefix boundary and the platform limits are in
[`README.zig.md`](README.zig.md) § "Runtime loading".

`-Druntime` is declared in `build.zig` and defaults to off. **The own-provider
route has been gated; nothing else on it has.** Eight cells of
`20261004T232823091897Z-23133` built it with `-Druntime=true` and ran `tests.zig`
against this tree's own `libblake3.so.0.1.8`, loaded by explicit path: 6/6 in
every cell, four optimize modes and both linkages. No *independent external*
provider was accepted, the `runtime-test` lifecycle suite and the misuse runs have
not been executed, and the cross-configuration ABI question is still
source-confirmed rather than measured.

### Nix and devenv

`devenv` is the canonical development shell:

```sh
direnv allow          # once, in this directory
devenv shell          # or: nix-direnv
```

Tasks are namespaced; the packaging route is `devenv build outputs.*`:

```sh
devenv run sdk:build     # zig build
devenv run sdk:test      # zig build test
devenv run sdk:check     # zig build check (six-target compile-only)
devenv build outputs.static   # the packaging route
devenv build outputs.shared
```

Every task runs in this directory rather than wherever the caller was standing,
and reaches the compiler with `-j8`, `--summary all` and both cache directories
written out: `--cache-dir "$ZIG_LOCAL_CACHE_DIR/blake3"` and
`--global-cache-dir "$ZIG_GLOBAL_CACHE_DIR"`, so nothing falls back to this SDK's
own `.zig-cache`. An exported `ZIG_LOCAL_CACHE_DIR` or `ZIG_GLOBAL_CACHE_DIR` is
used unchanged; a missing one is filled from `XDG_CACHE_HOME`, then from
`TMPDIR`, and the task refuses to run before the compiler when neither names a
location. `sdk:build` — the only task whose step installs, because a bare
`zig build` *is* the install step — also passes
`--prefix "$ZIG_LOCAL_CACHE_DIR/blake3-prefix"`, so no task writes `zig-out/`
here either. This is read out of `devenv.nix` as written; no task has been run
since, so it is a description and not an observation.

`package.nix` is the one derivation; `flake.nix` and `devenv.nix` both call it
with `pkgs.callPackage`, differing only in the `linkage` they pass.

```sh
nix build .#static
nix build .#shared
```

`default` resolves to the static variant, preserving this SDK's existing linkage
policy. The derivation runs `zig build install` and nothing else: the native
library, `blake3.h`, `libblake3.pc` and the six licence and provenance files under
`share/licenses/blake3/` are all written by the build graph, once. It passes
`-Dlinkage`, one `-Doptimize`, `-Dcpu=baseline`, `-j${NIX_BUILD_CORES:-1}` and
`--prefix $out`; it never passes `-Dsystem`, so a system library can never stand
in for a source result.

`-Druntime` is not passed by either variant. That is about the artefact, not
about executing host tools: building from source legitimately runs host build
tools, and `package.nix` does build from source. `-Druntime` would additionally
generate a dispatch, which is a consumer-side configuration and not part of this
library's delivery, so the derivation makes no claim about it.

`flake.lock` is present in this working copy, carrying one `github:NixOS/nixpkgs`
pin at revision `c7def046b9a883d46974757852106483d741586f`, and `build.zig.zon`
names it in `.paths` because it exists. Lock files are the driver's to write, not
authored material of this fork. `devenv.lock` is still absent, because
`devenv.yaml` pins its nixpkgs revision in source.


---

## Licence

Upstream offers three grants for its own work — CC0 1.0, Apache 2.0, or Apache
2.0 with the LLVM exceptions — and all three texts ship verbatim as
`LICENSE_CC0`, `LICENSE_A2` and `LICENSE_A2LLVM`.

Every file this fork authored is offered by its owner under the same three-way
choice: `CC0-1.0 OR Apache-2.0 OR Apache-2.0 WITH LLVM-exception`. No upstream
author is claimed as the author of any fork-authored file, and no personal
copyright identity was invented for one. See [`FORK-LICENSE.md`](FORK-LICENSE.md)
and [`NOTICE.md`](NOTICE.md).

**BLAKE3 is not a password hashing algorithm** (upstream's own warning,
`README.upstream.md:80-83`). The keyed mode is a fast MAC, and upstream
recommends Argon2 for passwords.

This package is local, uncommitted and unpublished: nothing has been published,
and no publication is authorized.