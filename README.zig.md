# blake3 — the BLAKE3 C library, built and wrapped in Zig

This package compiles BLAKE3 **1.8.7** — upstream's own C, byte for byte, from
the `c/` directory in this repository — and publishes a small, allocation-free
Zig facade over the translated `blake3.h`. No part of the hash function is
reimplemented, nothing is downloaded at build time, and there is no dependency
of any kind in `build.zig.zon`.

Upstream: `https://github.com/BLAKE3-team/BLAKE3`, tag `1.8.7`, commit
`f3149ec5bb5449af877ba20377a11008ff499fa2`. Provenance, licences and the
integrity record are in [`UPSTREAM.md`](UPSTREAM.md), [`NOTICE.md`](NOTICE.md),
[`FORK-LICENSE.md`](FORK-LICENSE.md) and [`UPSTREAM.sha256`](UPSTREAM.sha256).

This file is the interface documentation: commands, routes, the API and its
contracts, the linkage and runtime modes, and the verification record. The fork
README — native-source and native-build deviations, the support matrix and how
to consume the package — is [`README.md`](README.md); upstream's own README,
preserved byte for byte, is [`README.upstream.md`](README.upstream.md).

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
| `zig build` | compiles the C library, installs `libblake3.a` (the default linkage) and `blake3.h` into `zig-out/`, and compiles the example |
| `zig build -Dlinkage=dynamic` | the same, installing a shared object instead of the archive; see § "Linkage" |
| `zig build -Druntime=true` | builds the facade with no library linked into its module, for a consumer that names its provider at run time; the library is still built and installed. See § "Runtime loading" |
| `zig build runtime-misuse` | runs `runtime/misuse.zig after-load <provider>` and requires exit 0 — the control that must succeed. It does **not** run `pre-load` or `linked-load`; nothing in this build gates those, see § "The two runtime programs" |
| `zig build runtime-test -Druntime=true` | runs `runtime/load_tests.zig`. Needs `BLAKE3_TEST_PROVIDER` and `BLAKE3_TEST_ALIEN` exported by the caller — the build inherits them and cannot set them; without them the step fails rather than skipping |
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

It has been run three times. The first full matrix compiled all 53 targets and
then failed two of them on a deadline rather than on an answer; the corrected
matrix (`run_id=20261002-055258-61044-19309`, 2026-10-02) built all 53 with exit 0
and **executed this package's six tests on 20 of them — 6/6 each, zero
failures**; the current source-bound cohort (`20261004T221720228710Z-45046`,
receipt `blake3-53-target-8.json`, `--jobs 8 --build-jobs 8`) reached the same
shape against this tree's own source: **53 targets, 20 runtime PASS
(`reason: tests_complete`), 33 `build_only` (`runtime_unavailable`), 0 fail**,
run exit 0, `source_unchanged: true`, `jobs_honoured: true`. The same twenty
platforms ran in both. The other 33 are `build_only`: compiled, not executed,
because this host has no native, emulated or emulating runner for them, which is
a compile result and never a test pass. A green 53-target build is not 53 runtime
passes.

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

The current cohort's own record is `blake3-53-target-8.json` in epoch
`20261004T221720228710Z-45046`, with a per-target build log beside its summary. It
names the same twenty executed platforms and records the reason for each of the
other thirty-three.

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

### Routes into this package

| Route | What it is | When it exists |
|---|---|---|
| `dep.module("blake3")`, reached as `@import("blake3")` | the Zig facade in `zig/root.zig`, with the translated header bound to it as `blake3.c` and the library linked behind it | every Zig consumer, in a linked build |
| the same module, built with `-Druntime=true` | the same facade and the same translated header, with **no** archive or system library linked behind them: each selected native entry point becomes a dispatch through one process-lifetime table that an explicit `load` fills | a Zig consumer that names its provider at run time. The library is still built and installed — see § "Runtime loading" |
| `dep.artifact("blake3")` | the native library this package compiles | bundled mode only — a C-ABI route for a dependent that links the library into its own build |
| the installed `blake3.h` and native library under `zig-out/` | what `zig build` installs | bundled mode only — a C consumer that includes the header and links the library by path |

The translated header is not registered as a module of its own, so
`dep.module("c")` does not resolve: that route would hand a dependent the
declarations without the library that satisfies them. `blake3.c` on the facade
is the supported way to the raw header, and it carries the facade's own linkage.
In system mode nothing is compiled from this tree, so neither artifact route
exists — `dep.artifact("blake3")` has nothing to find, and `zig build`
installs nothing from this package. The example program is compiled and not
installed, so it is not an artifact route either.
Of the two artifact routes, the installed C layout is the one the
installed-C-surface row below actually compiled, linked and ran. The
`dep.artifact("blake3")` call is published and no row has exercised it from a
dependent, so nothing here reports it as working.

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
| `pub const c` | the raw translated header, for anything the facade does not name; the supported way to it, and not a module of its own |

**Valid state.** A `Hasher` is a constructed value, not an arbitrary block of
bytes. It is valid in the states `init`, `initKeyed` and `initDeriveKey`
return and the states `update` and `reset` derive from them; zeroed,
`undefined` or hand-built storage is not a valid hasher, and upstream carries
no flag that could tell the two apart. `Hasher` is `c.blake3_hasher` itself, so
its fields are reachable in Zig — a caller that writes them is holding its own
state, and none of what follows applies to it.

**Lifetime.** Nothing here allocates and nothing needs freeing, and there is no
`deinit` because there is nothing to release. Upstream allocates nothing, so
buffers go in and bytes come out and the caller owns all of them. A `Hasher` is
returned by value or borrowed through a pointer, and a copy is an independent
hasher: updating or resetting one leaves the other exactly as it was, either
may be finalized on its own, and no stable address is required. It is plain
mutable state with no locking, so one hasher belongs to one thread at a time.
`finalize` takes `*const Hasher` because upstream finalizes through
`const blake3_hasher *`: finalizing does not disturb the state, and a caller may
finalize the same hasher as often and at as many lengths as it likes.

**Buffers.** `update` borrows `input` for the call and does not retain it:
upstream copies what it has not compressed yet into the hasher's own buffer
(`c/blake3.c:35-45`), so the caller may overwrite or free the slice as soon as
the call returns. That copy is a `memcpy`, so `input` must not overlap the
hasher's own storage. `finalize` and `finalizeSeek` write exactly `out.len`
bytes into the caller's buffer, keep no reference to it afterwards, and require
the same non-overlap.

**Bounds.** There is nothing to check at run time, which is why there is no
error union: the key length is an array type, the output length is the length of
the caller's own slice, and the context length is passed explicitly. The facade
writes exactly `out.len` bytes and nothing outside it, a zero-length `out` writes
nothing (upstream checks for that itself before touching the pointer), and an
empty `update` is a no-op. Every public contract here is enforced by ordinary
types and ordinary comparisons that survive an optimized build; no
`std.debug.assert` guards anything a caller can reach.

**Errors.** None, and that is upstream's shape rather than an omission: every
`blake3_hasher_*` entry point in `c/blake3.h:64-80` is `void` and none of them
can fail. The one declaration in that block that returns anything is
`blake3_version` at `c/blake3.h:63`, a NUL-terminated string naming the library
that got linked. Inventing an error union would mean reporting conditions that
cannot occur.

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

  In this mode `-Dlinkage` does not select what this build produces — nothing is
  produced here — but names the kind of **installed** library to bind to, and
  defaults to `.dynamic`, which is what `linkSystemLibrary` already defaults to
  (`lib/std/Build/Module.zig:359`). So the behaviour a caller gets by passing
  nothing is the one this package has always had, and `-Dlinkage=static` is the
  single thing that changes it: to bind `libblake3.a`, which is what the
  option's name says in this mode.

### Linkage: `-Dlinkage=static|dynamic`

Selects the native delivery. `static` is the default and is what this SDK
produced before the option existed, so no existing consumer's linkage changes.

* `-Dlinkage=static` — a static archive, `libblake3.a`.
* `-Dlinkage=dynamic` — a shared object built with real PIC and real exports, so
  the installed layout is a loadable library rather than an archive. Shared
  delivery carries its whole closure: the per-instruction-set kernel objects and
  the core sources are all compiled position-independent and exported together.
  Nothing is dropped to make the shared build succeed.

The shared build reproduces upstream's own ABI numbering, which is the numbering
that matters to a consumer's `DT_NEEDED`: `c/CMakeLists.txt:150-155` sets
`VERSION ${PROJECT_VERSION}` and `SOVERSION 0` for version 1.8.7.

| Platform | Files installed |
|---|---|
| ELF | `libblake3.so.0.1.8`, the soname `libblake3.so.0`, and the `libblake3.so` symlink beside them |
| Darwin | `libblake3.0.dylib` with `libblake3.dylib` beside it, `install_name` `@rpath/libblake3.0.dylib` |
| Windows | `blake3.dll` and the import `blake3.lib`; no symlinks, which the platform has none of |

**The boundary, stated honestly.** The ABI major — the number a consumer's
`DT_NEEDED` records — is `0`, exactly as upstream's `SOVERSION 0` says. The file
name's patch component reads `8`, not `8.7`: `std.SemanticVersion` carries three
components and upstream's file name has four. That is upstream's own numbering,
reproduced rather than invented; it is not a claim that the two file names are
interchangeable.

Both variants install the same `blake3.h`, so the header does not change with
linkage, and both install `libblake3.pc` at `<prefix>/lib/pkgconfig/`. That file
is upstream's own `c/libblake3.pc.in` with `prefix` made relocatable, its
`Version:` formatted from the version read out of upstream, `Libs: -L"${libdir}"
-lblake3` in both variants (the library name does not change with linkage),
`Cflags: -I"${includedir}"` for static and the same plus `-DBLAKE3_DLL` for
dynamic — which is what upstream appends under `BUILD_SHARED_LIBS`
(`c/CMakeLists.txt:139-145`). `Requires:` is empty: upstream fills it only with
oneTBB (`c/CMakeLists.txt:256`), which is upstream's own default off
(`c/CMakeLists.txt:20`). There is no `Libs.private:` — upstream's template has
none and BLAKE3 depends on nothing but libc. There is no CMake export set: those
are CMake-internal target exports (`c/CMakeLists.txt:298-318`), not link
metadata a C or Zig consumer uses.

**One version, checked, not four copies of it.** `Version:` is formatted from
the version this build read out of upstream — the same 1.8.7 that
`c/blake3.h:33` and `c/CMakeLists.txt` declare — and `build.zig.zon`'s
`.version` is compared against it at configure time and panics on a mismatch
(`build.zig:1273-1276`). So the manifest, the shared object's file name, the
pkg-config file and this documentation cannot drift apart silently. A panic is
the right failure here: a build whose own version fields disagree has no honest
answer to give a consumer, and one that guessed would be worse than one that
refuses to configure.

**One target resolves the shared request back to static.** WASI has no dynamic
linker — `std.Target.DynamicLinker.kind` is `.none` for it — so a shared object
built there is a file nothing can load. `deliveredLinkage` (`build.zig:1452-1457`)
turns a `.dynamic` request into `.static` for such a target, and the build says
so at configure time. `zig build check` walks a WASI target, so the boundary is
reachable from the published six-target matrix, and it surfaces as a
configure-time message rather than a link error. Because one function decides
the delivered linkage for both the artifact and the translation, they cannot
disagree about which one they are.

**The export surface is the header's, not a list.** Every C translation unit is
compiled with `-fvisibility=hidden` on the shared variant, and upstream's
`BLAKE3_API` widens to `__attribute__((visibility("default")))` under GCC and
Clang (`c/blake3.h:20-22`), so exactly the entry points the header decorates are
exported and the internal cross-translation-unit symbols the kernels and
`c/blake3_dispatch.c` share (`c/blake3_impl.h:258-308`) stay private. The flags
go through one function so a kernel cannot be compiled with different
visibility from the core. No version script and no hand-written export list is
involved: the header already says which symbols are public, and a second list
beside it could only drift. On Windows `-fvisibility` does nothing and the export
surface comes from the `BLAKE3_DLL` / `BLAKE3_DLL_EXPORTS` macros, split the way
upstream splits them at `c/CMakeLists.txt:139-145`.

**This is a deliberate deviation from upstream, on the static build.**
Upstream sets `C_VISIBILITY_PRESET hidden` unconditionally
(`c/CMakeLists.txt:150-155`), so upstream's own static archive carries the flag.
This build applies it to the shared delivery only, for two reasons recorded at
`build.zig:346-359`: the static command line is the one every gate in this
repository's recorded history observed, and adding a flag to it would change a
verified build for no observable gain — visibility is inert for an archive,
because a hidden symbol in an archive is still linkable and an archive has no
dynamic symbol table to narrow. So the deviation is confined to an inert
property of the static artifact, and the artifact that actually has an export
surface matches upstream exactly.

The static build's C command line is therefore unchanged from before `-Dlinkage`
existed. `FORK-NOTES.md` §19 records how this was found and settled; what remains
open is the gate, not the decision.

**Observed for delivery; not yet observed by inspection.** The shared object was
built and installed in all four optimize modes by `20261004T233628757747Z-69351`,
and the loader opened that exact `libblake3.so.0.1.8` in all eight `-Druntime=true`
cells of `20261004T232823091897Z-23133`. The export table, the relocations and the
installed layout above are still **PENDING-VERIFICATION** in the sense that
matters: no gate has dumped them. They are what the build is written to produce,
and a successful load proves only that the surface carries what this facade calls.

### Runtime loading: `-Druntime=true`

`-Druntime=true` is declared in `build.zig`, defaults to off, and is independent
of `-Dlinkage`. Under it the facade links **no** native library into its module —
neither the archive this tree compiled nor an installed system library — so the
provider is named at run time by the caller. The library is still built and
installed: a caller may name a provider this tree did not build, and may equally
name the one it did. In a linked build nothing changes: calls are direct, there
is no table and no readiness check. The configure-time line says which of the
two you are in, so "the library is still installed" cannot be misread as "the
module links it":

```
blake3: runtime-loaded dispatch (-Druntime=true); no library is linked into the module
```

**What the option selects.** `build.zig` calls `runtime/graph.zig`'s
`createModule(b, translate, target, optimize)` in place of
`translate.createModule()`, and that call is the only place the generated
runtime dispatch takes over.

**The dispatch is generated per target, from that target's own translation.**
`runtime/generate.zig` is a host program — `b.graph.host`, `graph.zig:171-182` —
that the build runs over the translate step's real output, so a foreign
`-Dtarget` still produces a dispatch describing *that* target's header
configuration rather than the host's. Nothing is cached across configurations:
a different header configuration gives a different translation step output,
which gives a different dispatch. Two consequences worth naming: the build needs
a runnable host to generate for a foreign target, and `package.nix` never passes
`-Druntime`, which is one more reason the derivation makes no claim about this
route.

**One copy of the native types, not two.** The dispatch imports the translation
as `c_native` and re-exports its types and constants rather than restating them
(`graph.zig:147-149`), so `c.blake3_hasher` in a facade and `c_native.blake3_hasher`
in the dispatch are the *same* type. Two nominally distinct copies of a struct
layout, then cast between, is the failure mode this avoids.

**One core-module instance per build, and that is why the `rt` import is
branched.** `graph.createModule` creates the *one* core module the generated
dispatch uses and re-exports `LoadSource` and `LoadError` from it, so in the
runtime branch `build.zig` imports only `c` and adds no `rt` import of its own: a
second core module created for the facade would make its `LoadSource` a
nominal, different type, and `blake3.load(source)` would be handing the facade's
type to a function expecting the dispatch's. In the linked branch there is no
dispatch, so `createCoreModule` is imported as `rt` and the facade's
`zig/root.zig` names `LoadSource` and `LoadError` from it, choosing between the
two with a comptime branch on `runtime_loaded`. Whichever module a configuration
does not need is never resolved and never compiled.

This is a real constraint, not an implementation detail: **one instance of this
SDK's runtime state per build.** A second one in the same binary needs the
prefix below changed too.

**One prefix, stated twice, on purpose.** `runtime/sync.c` is compiled into the
dispatch with `-DRT_SYNC_PREFIX=blake3_rt`, and `runtime/library.zig` names the
resulting symbols `blake3_rt_lock`, `blake3_rt_unlock`, `blake3_rt_wait`,
`blake3_rt_signal`, `blake3_rt_broadcast` and the thread-identity function by
hand. Two spellings of one prefix have to agree; a build where they disagree does
not link, and that is the whole error report — there is no runtime path that
could paper over it. The core in `runtime/loader.zig` names no symbol of its
own, which is what lets two *different* SDKs hold their own loader state in one
process without sharing any of it.

**The consequence, and it is this SDK's own:** two instances of *this* library
in one binary collide on the `blake3_rt` prefix, so a second independent
instance needs the macro in `graph.zig` and the bound symbol names in
`library.zig` changed together. That is a real limit of the design, not an
oversight, and it is recorded here rather than discovered at link time.

Everything below describes the contract the sources implement. **Status: partly
observed.** A runtime-loaded consumer of this tree's own provider has been built
and run — eight `-Druntime=true` cells in `20261004T232823091897Z-23133`, four
optimize modes and both linkages, each loading `libblake3.so.0.1.8` by explicit
path and reporting 6/6 — and no independent external provider was accepted for
this SDK (`20261004T232439Z`, zero routes counted as external coverage). Every
failure, retry, idempotence, provider-change, atomic-publication and release-mode
panic check below still describes the sources rather than an observation: they
are what `runtime-test` would execute, and no cohort asked for that step.

```zig
// runtime-loading build
blake3.load(.{ .path = "/abs/path/to/libblake3.so.0.1.8" });
blake3.load(.{ .system = "libblake3.so.0" });
```

| Name | Shape | What it is |
|---|---|---|
| `runtime_loaded` | `bool`, `false` in a linked build | whether this build has the runtime route at all; a dependent can branch on it at comptime |
| `LoadSource` | `union(enum) { path: []const u8, system: []const u8 }` | an explicit absolute file path, or an explicit basename handed unchanged to the platform loader |
| `load(source)` | `LoadError!void` | the only entry point. There is no owning `Library` object, no returned API view and no public unload |
| `loadedSource()` | `?LoadSource` | the retained request once ready, `null` before |
| `LoadError` | `error{EmptySource, OpenFailed, MissingSymbol, ProviderMismatch, ReentrantLoad}` | see below |

**No fallback, in either direction.** `.path` is never retried as a basename,
`.system` is never resolved against a directory, and a failed load never
silently uses a linked copy. In a linked build `load` exists and stops the
program with an explicit panic rather than pretending to succeed.

**The errors.** `EmptySource` — the request names no file. `OpenFailed` — the
platform loader refused that file; a path to a static archive lands here, which
is the honest answer rather than a fallback. `MissingSymbol` — the file opened
but a required export was absent. `ProviderMismatch` — a load has already
succeeded and a *different* source was named. `ReentrantLoad` — called from a
thread already inside a load attempt.

**The ABI this route supports.** The provider must be a dynamically loadable
object exporting these nine symbols — the public extern route of the translated
header:

```
blake3_version
blake3_hasher_init
blake3_hasher_init_keyed
blake3_hasher_init_derive_key
blake3_hasher_init_derive_key_raw
blake3_hasher_update
blake3_hasher_finalize
blake3_hasher_finalize_seek
blake3_hasher_reset
```

`blake3_hasher_update_tbb` is **not** required: it sits behind
`BLAKE3_USE_TBB` (`c/blake3.h:72-75`), which neither mode defines. That is a
deliberate statement about the one ABI family this configuration supports — the
plain C library's public entry points — not a claim that every BLAKE3 build
exports the same set. A provider built with oneTBB, or the Rust crate rather
than the C library, is a different ABI family and is not claimed here.

**These nine are the same nine the shared delivery exports.**
`c/blake3.h:63-80` decorates exactly nine entry points with `BLAKE3_API`, plus
`blake3_hasher_update_tbb` behind `#if defined(BLAKE3_USE_TBB)` (`:72-75`). The
list above is those nine, in the header's own order. So a shared object built by
this build exports precisely the set a runtime-loaded consumer of it requires:
no third entry point to reconcile, and no name spelled here that the header does
not declare. That is a correspondence between two readings of one header, not a
runtime observation — no provider has been loaded.

**Header, layout, config and scalar prerequisites.** The provider must have been
compiled against the same `blake3.h` as this build, so `blake3_hasher` and
`blake3_chunk_state` layouts, the `BLAKE3_*` constants and the `size_t`/`uint64_t`
widths are the ones the translated header fixed, and with the same configuration
macros (`BLAKE3_MAX_DEPTH`, `BLAKE3_BLOCK_LEN`, `BLAKE3_OUT_LEN`,
`BLAKE3_KEY_LEN`). The SIMD kernel choice does not change the ABI. Validation at
load is `blake3_version()` resolving to a non-NULL, non-empty, NUL-terminated
string. **Symbol lookup plus a version string plus a release text is not ABI
proof**; the header translation is the boundary being asserted.

**Allocator and libc.** None. The loader allocates nothing — a stack frame and a
fixed inline source record — so there is no `deinit` and nothing to free, and the
byte slices a caller passes live only for the call. The only libc dependency is
the platform loader itself: a statically linked musl or a `-static` binary has no
`dlopen` and cannot use this route at all.

### The two runtime programs, and what is gated

`runtime/` carries two programs beyond the library, and they are gated
differently on purpose.

**`runtime/load_tests.zig`** is an `addTest` root wired **only** under
`-Druntime=true`, behind the step `runtime-test`. Its own comptime guard refuses
to compile against a linked module, so wiring it unconditionally would be wiring
a compile error. It runs against real providers, not mocks: the graph compiles
the library a second time as a shared object and passes that as the provider,
and `BLAKE3_TEST_ALIEN` is meant to name a real loadable object that is *not*
BLAKE3, because `MissingSymbol` is about exactly that case and a mock would not
be one.

`BLAKE3_TEST_PROVIDER` and `BLAKE3_TEST_ALIEN` are **inherited from the
caller's environment, not set by the build**. `Step.Run` in this Zig release
takes only literal strings in an environment map (`Run.zig:595-598`), with no
API for a build-time-resolved path, and `load_tests.zig` fails loudly when one
is missing — which is what its own header specifies. So:

```sh
zig build -Dlinkage=dynamic --prefix <dir>      # build a provider to point at
export BLAKE3_TEST_PROVIDER=<dir>/lib/libblake3.so.0.1.8
export BLAKE3_TEST_ALIEN=<path to a loadable object that is not BLAKE3>
zig build runtime-test -Druntime=true
```

Without those two exported the step fails; it does not skip.

**`runtime/misuse.zig`** is compiled in **both** configurations, because its
`linked-load` mode asserts the message a *linked* build produces and a
runtime-only build cannot check that half. It is install-depends-on, not
installed as a deliverable. The step `runtime-misuse` runs only
`after-load <provider>` with `expectExitCode(0)`: the same call that must
succeed once a real provider is in.

**What no build step gates, and why.** `pre-load` and `linked-load` are compiled
in every configuration and every optimize mode, but nothing in this build runs
them. Their whole assertion is that the program *stops* — `Step.Run` exposes
only `expectExitCode(u8)` (`Run.zig:628-631`) and has no "must not exit zero"
check, so gating them would mean writing down an exit code nothing has
observed. **They are driver-run and driver-observed**, and
`zig build check -Druntime=true` compiles both programs for all six matrix
targets, because `add_target_check` builds through the same `add_graph`.

So `runtime-misuse` covers the control only. A gate table that lists it as
covering the misuse case would be claiming a result nobody produced.

The same is true of the **pre-readiness panic**: `pre-load` is the only thing
that reaches a call before any load, so it is the only route by which the
panic can be observed — and it has to be observed once per optimize mode,
including `ReleaseFast` and `ReleaseSmall`, because a panic guard that survives
optimization is exactly the property those two modes exist to test.

**Status: partly observed.** The wiring above is read out of the landing source,
and one route has since been run: the eight cells of `20261004T232823091897Z-23133`
built this graph with `-Druntime=true`, four optimize modes times both linkages,
with `BLAKE3_TEST_PROVIDER` naming this tree's own `libblake3.so.0.1.8` and
`BLAKE3_TEST_ALIEN` naming `/lib64/libm.so.6`. In every cell `tests.zig` called
`blake3.load(.{ .path = … })` before its first test and reported 6/6. That covers
the route, not these programs: those waves asked for `test smoke install`, so
`runtime-misuse` and `runtime-test` — and therefore `load_tests.zig` and
`core_tests.zig` — were never executed, and the two misuse modes that must stop
remain driver-run. No independent external provider was accepted
(`20261004T232439Z`: zero routes counted as external coverage).

## Verification status


### What this migration changed, and what has been re-gated since

The migration added `-Dlinkage`, the runtime route, and Nix and devenv
packaging. The first table below is the set of gates that change owes: each row
carries either the epoch that closed it and what that epoch actually observed, or
**PENDING-VERIFICATION** — landed, no gate has looked at it. The second table is
the historical record: observations taken on the dates named, against the tree as
it stood then. The two are kept apart, and no historical row is restated as a
current one.

The cohorts behind the closed rows are `20261004T221720228710Z-45046` (the
53-target matrix, receipt `blake3-53-target-8.json`), `20261005T014547Z-797a73f2`
(the compile-only baseline, row `baseline-blake3-check`),
`20261004T233628757747Z-69351` (eight linked cells) and
`20261004T232823091897Z-23133` (eight `-Druntime=true` cells). The
external-provider probe is `20261004T232439Z`, receipt `blake3-index.json`.

| Gate | Command to run | Status |
|---|---|---|
| static, all four optimize modes | `zig build test smoke install -Doptimize=<mode> -Dlinkage=static` | **OBSERVED — 4/4 cells**, `20261004T233628757747Z-69351`: each exit 0, 28/28 steps, 6/6 tests, `smoke success`, and a 9-file prefix carrying `lib/libblake3.a`, `libblake3.pc`, `blake3.h` and the six licence and provenance files |
| shared, all four optimize modes | `zig build test smoke install -Doptimize=<mode> -Dlinkage=dynamic` | **OBSERVED — 4/4 cells**, same epoch: each exit 0, 28/28 steps, 6/6 tests, `smoke success`, and an 11-file prefix carrying `lib/libblake3.so`, `lib/libblake3.so.0`, `lib/libblake3.so.0.1.8`, `libblake3.pc`, `blake3.h` and the same six files |
| shared export table and closure | inspect the shared object's exported symbols and relocations; confirm the per-ISA objects and the core are all inside it | **PARTLY OBSERVED.** Built and installed in all four modes, and the loader opened `libblake3.so.0.1.8` — the same file, by digest — in all eight `-Druntime=true` cells of `20261004T232823091897Z-23133`, which is a functional proof that the export surface carries every entry point this facade calls. The inspection itself has not been run, and no receipt names a relocation. |
| typed and raw consumer | the separate `consumer/` package, and one that reaches `blake3.c` directly | **PENDING-VERIFICATION** — no cohort above ran `consumer/`; all sixteen cells ran `test smoke install` from this package root |
| installed C consumer, both linkages | compile and run a C program against the installed header and the static archive, then against the shared object | **PENDING-VERIFICATION** — the install layout is recorded per cell, exactly as the two rows above name it, but no cohort compiled or ran a C program against an installed prefix. The last receipt is the 2026-10-01 row below, static only. |
| runtime-loaded consumer | own shared object, and a compatible external provider, each loaded by explicit `.path` and by explicit `.system` | **Own shared object — OBSERVED:** `20261004T232823091897Z-23133`, 8/8 cells — four optimize modes times both linkages, `-Druntime=true`, `BLAKE3_TEST_PROVIDER` naming this tree's own `libblake3.so.0.1.8`, `BLAKE3_TEST_ALIEN` naming `/lib64/libm.so.6` — each reporting 6/6 with `tests.zig` performing the explicit-path load before its first test. **Compatible external provider — NOT EXERCISED, a boundary and not a pass:** no independent external provider was accepted; in `20261004T232439Z` every route carries `counts_as_external_coverage: false`, `external_successes_observed` is 0, the one success is `path-01-libblake3.so.0.1.8-success` with `independence: own`, and the three declared external candidates were the expected refusals across six routes by `.path` and by `.system`. |
| loader behaviour | startup, failure, explicit retry, idempotence, provider change, atomic publication, and the pre-readiness panic in `ReleaseFast` and `ReleaseSmall` as well as Debug and ReleaseSafe | **PENDING-VERIFICATION.** The eight loaded cells show that one load, by explicit path, reaches a real provider and that the published vectors survive it. Everything the contract is about *between* calls lives in `runtime-test`; the per-mode pre-readiness panic lives in `pre-load`. Neither has been run. |
| loader's own tests | `zig build -Dlinkage=dynamic --prefix <dir>`, export `BLAKE3_TEST_PROVIDER` and `BLAKE3_TEST_ALIEN`, then `zig build runtime-test -Druntime=true` | **PENDING-VERIFICATION.** Neither 8-cell wave asked for the `runtime-test` step, so `runtime/load_tests.zig` and `runtime/core_tests.zig` have not been executed |
| misuse control | `zig build runtime-misuse` — `after-load <provider>` must exit 0. Control only; see § "The two runtime programs" | **PENDING-VERIFICATION.** `blake3-misuse` compiled in all sixteen cells of the two 8-cell waves, and `runtime-misuse` was never among the steps those waves asked for |
| misuse, driver-run only | run `runtime/misuse.zig pre-load` and `linked-load` directly, in **all four** optimize modes; each must stop and name the library, the function and the way out. No build step covers these, and this row is also the only way the pre-readiness panic gets observed per mode | **PENDING-VERIFICATION** — no cohort above ran either mode |
| behavioural gate after the change | `zig build test`, `zig build test -Doptimize=ReleaseSafe`, `zig build test -Dportable=true` | **PARTLY OBSERVED.** Debug and ReleaseSafe are the two linked cells of `20261004T233628757747Z-69351`, 6/6 each. `-Dportable=true` was in no cohort above; its last receipt is the 2026-10-01 row below, which predates the current `build.zig`. |
| six-target compile-only matrix | `zig build check` for each baseline triple | **OBSERVED, compile-only.** `20261005T014547Z-797a73f2`, `baseline-blake3-check`: exit 0, `failed: false`, 47/47 steps, all six triples at six steps each, no failing step line, no diagnostic, `runtime_pass_claimed: false` and an empty `test_pass_lines`. One invocation with no `-Dtarget`, so it walked the graph's own whole-matrix step rather than one target. |
| full 53-target matrix | `cross-test` from the package root | **OBSERVED.** `20261004T221720228710Z-45046`, `blake3-53-target-8.json`: **53 targets — 20 runtime PASS (`reason: tests_complete`, six tests each), 33 `build_only` (`runtime_unavailable`), 0 fail, run exit 0**, `source_unchanged: true`, `jobs_honoured: true`. A green build of all 53 plus 20 executions, on the same twenty platforms as the 2026-10-02 row. Not 53 test passes. |
| fetched filtered consumer | `zig fetch` this package, then build and run the consumer inside the materialised copy | **PENDING-VERIFICATION** — no cohort above fetched this package |
| devenv shell | `devenv shell`, and each declared task | **PENDING-VERIFICATION** — no cohort above entered a shell or ran a task |
| Nix static derivation | `nix build .#static`, then inspect the output and `nix-store --query --references` | **PENDING-VERIFICATION** — no derivation has been evaluated or built |
| Nix shared derivation | `nix build .#shared`, same inspection | **PENDING-VERIFICATION** — same |

Read together, the closed rows establish that this tree builds all 53 published
platforms, runs its six published-vector tests on 20 of them, builds and installs
both linkages in all four optimize modes, and reaches a real provider through the
loader in all eight runtime-loaded cells. They establish nothing about
`-Dsystem=true`, about an independent external provider, about the loader's
between-calls contract, about a Zig or C consumer built against an installed
prefix, or about either Nix derivation or the devenv shell. Every one of those
rows above reads `PENDING-VERIFICATION`, which is this tree's current state and
not a summary of older ones.

The full support matrix in canonical order is `README.md` § "Build / run / test
matrix"; it is not duplicated here.

The historical table that follows records those observations. Every build row was
run in this workspace with `-j8` and `--summary all`, each against its own
`--cache-dir` on an approved scratch
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
| pristine upstream bytes | `git diff --exit-code f3149ec5… -- c test_vectors LICENSE_A2 LICENSE_A2LLVM LICENSE_CC0 README.md` — as run, before upstream's README moved to `README.upstream.md` | exit 0, no output: the shipped upstream files equal the pinned commit. A direct diff of this working tree against the pinned commit — not a replay of `git archive`, and not a CI run | `local://foundation-expansion-blake3-pristine-source-81.log` |
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
  and the matrix row are 2026-10-02 observations of this tree; the two
  `-Dportable=true` rows and the installed C-surface row are 2026-10-01. Since
  then the authored Zig layer has moved — `zig/root.zig` and `build.zig` carry
  the current declarations, contracts and routes, and `build.zig.zon` gained
  one line naming the cross-test profile — so those rows describe the tree as
  it stood rather than this one, and a fresh run is what would make any of them
  a result for it again. No C source, header, fixture, test, example or licence
  text has changed, which is what the integrity and pristine-bytes rows cover:
  they are still the 52 records of exactly the bytes the 2026-10-02 rows
  compiled. The six tests every test row counted are the six `tests.zig` holds,
  and `tests.zig` is one of the unchanged files.

  The first table in this section is where this tree's own current observations
  live: the 2026-10-04 53-target cohort, the 2026-10-05 compile-only baseline and
  both 8-cell waves all ran against this source, and the 53-target receipt records
  `source_unchanged: true` across its run.
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
directory, the fixture, the three licence texts and upstream's README, preserved
here as `README.upstream.md` — and nothing else, so the same command works in a
clone and in an unpacked package.
Both halves of that claim have been run here: `sha256sum -c UPSTREAM.sha256`
reported 52 records and no failures, and `git diff --exit-code` against the
pinned commit over `c`, `test_vectors`, the three licence texts and upstream's
README (as it was named `README.md` at the time, and is named
`README.upstream.md` today)
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
this fork narrows none of that and re-grants none of it.

This fork's own files — the build graph, the facade, the runtime loader and its
generated dispatch, the tests, the example, the consumer package, the Nix
packaging and this documentation — are offered by the fork's owner under the
same three-way choice, on the owner's authorization. No upstream author is
claimed as the author of any of them, and no personal copyright identity was
invented for one. The full grant, the authorization and the Apache-2.0 §4/§3
obligations are in [`FORK-LICENSE.md`](FORK-LICENSE.md); attribution, the
per-file inventory and the carried licence texts are in
[`NOTICE.md`](NOTICE.md).

An earlier revision of this README offered the fork's files under Apache-2.0
because that text happens to ship here — a grant nobody had authority to make,
since `LICENSE_A2` is upstream's grant over upstream's own work. `CHANGELOG.md`
§12 withdrew that offer and §17 records what replaced it.

BLAKE3 is **not** a password hashing algorithm (`README.upstream.md:80-83`); the
keyed mode is a fast MAC, and upstream recommends Argon2 for passwords.

## Packaging: Nix and devenv

`package.nix` is one injected derivation taking `linkage`; `flake.nix` and
`devenv.nix` both call it with `pkgs.callPackage` and differ only in the
`linkage` they pass. The build is this repository's own `zig build install` over
this repository's own `c/`. No `../` import, no host account or store path, no
build-time download, and nothing read from the environment at evaluation time.

| Attribute | What it is |
|---|---|
| `.#static`, `devenv build outputs.static` | the static archive, the linkage this SDK has always produced |
| `.#shared`, `devenv build outputs.shared` | the shared object |
| `.#default` | the static variant — the default preserves the existing linkage policy |

Each output installs what `zig build install` installs — the native library,
`blake3.h`, `libblake3.pc`, and the six licence and provenance files under
`share/licenses/blake3/`. One writer per path: the build graph owns all of them
and `package.nix` writes none of them itself.

The derivation passes `-Dlinkage=<variant>`, one `-Doptimize`,
`-Dcpu=baseline`, `-j${NIX_BUILD_CORES:-1}` and `--prefix "$out"`. It never
passes `-Dsystem`, so a system library can never stand in for a source result.

It does not pass `-Druntime`, and that is about the artefact rather than about
executing host tools: building from source legitimately runs host build tools,
and this does. `-Druntime` would additionally generate a dispatch, which is a
consumer-side configuration and not part of this library's delivery.

`devenv` is the canonical development shell; its `packages` list holds tools
only, so entering it never builds the library. Gates are namespaced tasks
(`devenv run sdk:build`, `sdk:test`, `sdk:check`, `sdk:runtime-test`), and
`outputs.*` are lazy, so the packaging route is `devenv build outputs.static`.

Every task body begins in this directory — devenv runs a task with the caller's
working directory, which is not this SDK — and passes `-j8`, `--summary all`,
`--cache-dir "$ZIG_LOCAL_CACHE_DIR/blake3"` and
`--global-cache-dir "$ZIG_GLOBAL_CACHE_DIR"`. An exported cache variable is used
unchanged; a missing one is filled from `XDG_CACHE_HOME`, then from `TMPDIR`,
and the task refuses to run before the compiler when neither names a location,
because `enterShell` does not run for `devenv tasks run --mode single <name>`.
`sdk:build` also passes `--prefix "$ZIG_LOCAL_CACHE_DIR/blake3-prefix"`, because a
bare `zig build` runs the install step; `sdk:test`, `sdk:check` and
`sdk:runtime-test` depend on no install step (`build.zig:1392,1445-1465,1472-1483`)
and pass no prefix. Source-confirmed: no task has been run since this change.

`flake.lock` is present in this working copy, carrying one `github:NixOS/nixpkgs`
pin at revision `c7def046b9a883d46974757852106483d741586f`, and `build.zig.zon`
names it in `.paths` because it exists. `devenv.lock` is absent, because
`devenv.yaml` pins its nixpkgs revision in source. Both are the driver's to write,
not authored material of this fork. **Status: PENDING-VERIFICATION** — nothing
here has been evaluated, built or run.
