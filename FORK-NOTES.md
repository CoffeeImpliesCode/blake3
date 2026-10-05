# FORK-NOTES.md — what actually went wrong, and what was decided

Problems met while packaging BLAKE3 as a Zig 0.16 package, and the decisions
they forced. Written in the shape a later wave can reuse: **condition,
symptom, cause, fix, what it is bound to**. Statuses are the workspace's:
`OBSERVED` (a driver run printed it, receipt named), `SOURCE-CONFIRMED` (read
out of a file, never executed), `PENDING-VERIFICATION` (landed, no gate has
looked at it), `NOT RUN` (no receipt exists at all).

Entries 1–3 are Zig-0.16-shape problems, and the pattern behind all three is
the one the workspace already knows: resolve an API or a grammar question by
reading the pinned compiler's own `lib/std` and the diagnostic it printed,
never from memory of an earlier Zig. No probe was run to find any of them.
Entries 9 and 10 are a different class: this build compiled on the host that
wrote it and failed on the very targets it was meant to cover, which is
`WISDOM.md` W20 arriving in a new library. Entry 13 is a third class again:
there the code was right on every one of the 53 platforms and the *deadline*
was wrong, so the fix was a number in the harness profile and not one line of
source.
Entries 14 to 19 are a fourth class again: nothing failed and nothing was run.
Each is a place where a record, a path, a metadata attribute or a build comment
can quietly assert something false — a digest filed against the wrong path, an
invented lock hash, a single-identifier label standing in for a three-way
licence choice, a gate written for an exit code the build API cannot express, a
comment that did not describe its code — and in each the failure is a false
statement rather than an error message.

---

## 1. An anonymous struct literal cannot be followed by another literal

**Condition.** The build script's option table was written as one anonymous
struct literal and then immediately continued with `.{...}`.

**Symptom.** Configure-time failure for every gate:

```
build.zig:190:2: error: expected ';' after declaration
}.{
 ^
```

Exit code 2, no C compiled, no Zig analysed.

**Cause.** A struct literal is a value expression; a declaration ends at `;`. Two
literals in a row are a parse error, not a concatenation.

**Fix.** A named type for the option rows and a typed literal for the list.
Named rather than anonymous so the row type is written once and the values are
checked against it.

**Bound to.** Zig 0.16's grammar. The same shape would be rejected by any Zig.

**Evidence.** `local://foundation-expansion-blake3-install.log`,
`-test-debug.log`, `-test-releasesafe.log`, `-smoke.log`, `-consumer.log`; all
exit 2.

**Status.** `OBSERVED` — the error is absent from every later run, each of which
fails later in the pipeline instead.

---

## 2. `std.fmt.bytesToHex` needs a comptime-known length

**Condition.** Three private helpers formatted a digest whose length comes from a
runtime slice length: `tests.zig`, `smoke.zig` and `consumer/src/main.zig`.

**Symptom.**

```
lib/std/fmt.zig:1156:53: error: unable to evaluate comptime expression
pub fn bytesToHex(input: anytype, case: Case) [input.len * 2]u8 {
                                               ~~~~~^~~~
lib/std/fmt.zig:1156:47: note: function return type must be comptime-known
tests.zig:151:38: note: generic function instantiated here
    const actual = std.fmt.bytesToHex(digest, .lower);
```

and the same two notes instantiated at `smoke.zig:133` and
`consumer/src/main.zig:131`.

**Cause.** The return type is `[input.len * 2]u8`, so `input.len` has to be
comptime-known for the function to instantiate at all. A runtime slice length is
not. This is a property of that one function's signature, not of formatting in
general.

**Fix.** Each helper owns a fixed stack buffer of `2 * len + 1` bytes and calls
`std.fmt.bufPrint("{x}", .{digest})` into it, then compares the hex text with the
published answer. `bufPrint` returns the number of bytes written, so a length
that ever exceeded the buffer would be caught at the call site rather than
truncated silently.

**Bound to.** the `bytesToHex` signature in Zig 0.16's `lib/std/fmt.zig`. A Zig
version that returned a slice or an `ArrayHashMap` would not need this.

**Evidence.** `local://foundation-expansion-blake3-test-debug.log`,
`-smoke.log`, `-consumer.log` (exit 1);
`local://foundation-expansion-blake3-initial-debug-12.log`,
`-test-releasesafe-29.log`, `-portable-debug-32.log` (exit 0, afterwards).

**Status.** `OBSERVED`.

---

## 3. An array value does not coerce to a slice; a pointer to one does

**Condition.** The example passed an array constant where the facade's parameter
is `[]const u8`.

**Symptom.**

```
smoke.zig:92:17: error: array literal requires address-of operator (&) to coerce to slice type '[]const u8'
    blake3.hash(three_byte_input, &digest);
```

**Cause.** `[_]u8{0, 1, 2}` is a value of array type and Zig does not implicitly
decay it; `&array` is a pointer to an array, and that does coerce to a slice. The
same rule is why the string literal in `README.zig.md`'s example
(`blake3.hash("hello", &digest)`) is fine — a string literal is already a
pointer to a sentinel-terminated array.

**Fix.** `&three_byte_input` at the call site. The constant stays an array, which
is what it is, and the address-of operator says "borrow this".

**Bound to.** Zig's coercion rules; not version-specific.

**Evidence.** `local://foundation-expansion-blake3-install-28.log`, `-smoke-30.log`,
`-portable-smoke-33.log` (all exit 1);
`local://foundation-expansion-blake3-repaired-smoke-35.log` (exit 0, afterwards).

**Worth noticing.** This error appeared only in `smoke.zig`, so it red-lined
exactly the gates that build the example (`zig build`, `zig build smoke`,
`zig build smoke -Dportable=true`) and left `zig build test` and the consumer
green. A compile error in one root is not a compile error in the others; the
gate list decides what a diagnostic actually tells you.

**Status.** `OBSERVED`.

---

## 4. One private hex helper per root, and why the buffer is `2 * len + 1`

**Decision.** `tests.zig`, `smoke.zig` and `consumer/src/main.zig` each format a
digest in one small local function with a fixed stack buffer, rather than sharing
a formatter through the facade.

The facade stays a wrapper: it has no formatting, no allocation and no
`std.fmt` dependency, so the library cannot grow a formatting surface that a
consumer has to carry. The duplication is three short functions in three
different roots, and it is deliberate — a shared formatter would have to live
either in the facade (wrong layer) or in a fourth file that exists only to be
imported by tests.

`2 * len + 1` is the exact size of the lowercase hex of `len` bytes plus the NUL
`bufPrint` writes; nothing is truncated and nothing is allocated.

**Status.** `SOURCE-CONFIRMED` (the code is in the tree, and it ran in every
passing gate).

---

## 5. The cross matrix needs one private module per target

**Fact.** `b.addModule(name, …)` registers the module under that name against
the whole build. Six matrix targets all registering `blake3` would leave the
last registration reachable and would silently stop checking the other five.

**Decision.** `add_graph(..., public)` takes a flag: the published graph uses
`b.addModule("blake3", …)`, and every cross-target check uses
`b.createModule(…)` with a private name, because a check needs the module to be
*compiled for that target*, not published once. The artifact is named per target
(`blake3-<triple>`) instead of `blake3`, so six steps called `blake3` do not make
`--summary all` unreadable.

**Also.** The check compiles `tests.zig` and `smoke.zig` for each target, not just
the archive: Zig analyses a function body only when something calls it, so a
`check` that compiled an unreferenced archive would prove nothing about the
facade. No target is skipped and none is pre-judged; there is no
`continue-on-error` anywhere in the workflow.

**Status.** `OBSERVED` — all six targets compiled, none of them run:
`local://foundation-expansion-blake3-isa-target-x86_64-linux-gnu-114.log` and
`-isa-target-x86_64-windows-gnu-115.log` (14/14 steps each, four kernel objects
each), `-target-aarch64-linux-gnu-73.log`, `-target-aarch64-macos-none-74.log`,
`-target-riscv64-linux-gnu-76.log` and `-target-wasm32-wasi-77.log` (6/6 steps
each). The first attempt at the two x86 targets was red and is entry 9. The
shape is read out of `build.zig:276-283` (the target list), `318-359` (published
versus private module) and `567-606` (one check per target, compiling the tests
and the example as well as the library).

## 6. System mode translates the header the mode actually links

**Fact.** `zig/translate.h` includes `<blake3.h>` and copies no declaration.
Bundled mode adds `-I c` to the translation; system mode does not.

**Decision.** That single include line plus the include path is how the two
modes end up translating different headers: the bundled header describes the C
this repository compiles, and the installed header describes the library the
machine has. A bundled 1.8.7 header against an older installed `libblake3`
would describe an ABI that may not exist on disk (`WISDOM.md` W14).

`systemIntegrationOption("blake3", .{ .default = system_default })` is the only
switch the branch reads; `-Dsystem=true` supplies that option's default on a
stock runner and is not a second code path.

**Known cost.** In system mode nothing is compiled from this tree, so nothing is
installed by it — `zig build` would produce no artifact from this package. That is
stated rather than papered over with an empty install.

**Status.** `SOURCE-CONFIRMED` (`build.zig:46-53` for the switch, `331-344` for
the include path that decides which header gets translated, `662-672` for the
option and the branch). **`NOT RUN`** — this workspace has no installed
`libblake3`, so no receipt exists and none is claimed. That is a fact about the
machine, not a verdict on the mode, and it must not be written up as one.

---

## 7. What the integrity record covers, and what it does not

**Decision.** `UPSTREAM.sha256` hashes exactly the upstream-owned entries of
`build.zig.zon` `.paths`: the whole `c/` directory, `test_vectors/test_vectors.json`,
the three licence texts and upstream's README, preserved here as
`README.upstream.md`. 52 records, one per file.

*Why not the whole upstream tree.* The Rust crate, the benches, the media, the
upstream CI and `CONTRIBUTING.md` are carried in the repository for provenance,
but they are not in `.paths`. A record naming files the package does not ship
would fail `sha256sum -c` in a dependent's fetched package, which is exactly where
an integrity record has to keep working.

*Why `.gitignore` is absent.* It is the one upstream file this fork edits
(entries appended), so it is not byte-identical to upstream and its digest would
bless the fork's own text as if it were upstream's. The append is recorded in
`NOTICE.md` and in the file's own header instead.

*Why the record does not hash itself.* A checksum file cannot contain its own
digest.

*How the digests were produced.* Each file was read as raw bytes with
`Bun.file(path).arrayBuffer()` and hashed with `crypto.createHash("sha256")` from
`node:crypto`, on 2026-10-01. No shell hashing command and no git command was
used. Every record was then re-derived from the written file and compared
against it, and the path set was compared against the tree walk, before this note
was written.

*What it proves.* That the bytes a build compiles and the fixture the tests read
are the bytes this record pins. *What it does not prove.* That they equal commit
`f3149ec5bb5449af877ba20377a11008ff499fa2` — that rests on the import and on the
`git archive` stream digest recorded in `UPSTREAM.md`, both produced by the
driver, not by anything computed here.

**Status.** `OBSERVED`. The gate ran: 52 records, no failures
(`local://foundation-expansion-blake3-immutable-integrity-80.log`). The weaker
question the record cannot answer — are those bytes the pinned commit's? — was
answered separately: `git diff --exit-code f3149ec5… -- c test_vectors
LICENSE_A2 LICENSE_A2LLVM LICENSE_CC0 README.md` — the path as it was named when
that ran; upstream's README is `README.upstream.md` today — printed nothing and
exited 0
(`…-pristine-source-81.log`). What still needs a re-fetch is the archive
digest, and `UPSTREAM.md` § "Archive receipt" says so.


## 8. What has not been observed

Recorded so a later reader does not mistake silence for a result. The current
state of every gate, green or not, is the one table in `README.zig.md` §
"Verification status"; it is deliberately not copied here, because a second
copy of a gate table is a second thing to keep wrong. Three things belong in this
file rather than in that table:

* **`zig build check` and `cross-test` are different gates and their receipts
  must not be merged.** `check` compiles the C core, the facade, `tests.zig` and
  the example for one target and runs nothing. `cross-test` builds the same
  graph with `zig build test -Dtarget=TARGET` and executes the binary wherever
  this host has a runner. A receipt naming `check` is compile evidence and never
  claims a foreign binary ran; a receipt naming `cross-test` carries the test
  count it actually observed.
* **`build_only` is a compile result.** In the cohort that is current for this
  tree — `20261004T221720228710Z-45046`, receipt `blake3-53-target-8.json` — 33
  of the 53 platforms have no runner on this host, and the 2026-10-02 cohort
  before it split the same way. Their rows say `build_only`, their test count is
  null, and no file in this fork counts one of them as a test pass. That is a
  fact about this machine, and it is not a claim that those platforms work or
  that they do not.

---

## 9. An x86 SIMD kernel cannot be one more source file on one module

**Condition.** The four C intrinsics kernels were added to the library's own C
module as four more sources, the way upstream's CMake build adds them behind a
`-m` flag per library.

**Symptom.** Everything on the build host passed — install, both test modes,
the smoke run, the consumer — and the two x86 cross targets failed:
`x86_64-linux-gnu` with 114 errors, `x86_64-windows-gnu` with 54, in two shapes:

```
c/blake3_avx2.c:236:7: error: AVX vector return of type '__m256i' (vector of 4 'long long' values) without 'avx' enabled changes the ABI
c/blake3_sse41.c:125:8: error: '__builtin_ia32_pblendw128' needs target feature sse4.1
c/blake3_avx2.c:20:42: error: always_inline function '_mm256_set1_epi32' requires target feature 'avx', but would be inlined into function 'set1' that is compiled without support for 'avx'
```

(`local://foundation-expansion-blake3-target-x86_64-linux-gnu-72.log` and
`-target-x86_64-windows-gnu-75.log`, both exit 1.)

**Cause.** A Zig C compilation takes its instruction set from its module's
resolved target; a `-m` flag on the command line does not widen a target that
does not already carry the feature. The shape that hides the fault is the
dangerous one: a build host that already has all four instruction sets resolves
a native target carrying all of them, so the identical source compiles there
and fails for every baseline x86 target. `WISDOM.md` W20 is this same lesson
from htscodecs, and Random123 paid a version of it for AES-NI.

**Fix.** One object per kernel, each with a target of its own. `kernel_target`
(`build.zig:396-406`) starts from the caller's resolved target, pins
`cpu_model = .baseline`, adds exactly that row's features and subtracts none;
`x86_kernels` (`build.zig:190-211`) is where the rows and their prerequisites
are named, including `.avx512f` **and** `.avx512vl` as two separate bits
(`c/README.md:329-330` says both are required, and
`c/blake3_avx512.c:1227` returns through an AVX512VL intrinsic).
`add_x86_kernel` (`build.zig:443-470`) builds each in a private module and adds
it to the library as an object named after the artifact and the instruction set,
so `--summary all` shows which instruction sets were built and for which target.
No `-m` flag is passed anywhere now; `resolveTargetQuery` supplies the
prerequisites the target table declares, which is why `.sse4_1` arrives with
the `.ssse3` that `c/blake3_sse41.c:31` needs and a bare `-msse4.1` never
delivered.

**Why the library's own target is not raised.** `c/blake3.c`,
`c/blake3_dispatch.c` and `c/blake3_portable.c` keep the caller's requested
baseline, which is the entire point of upstream's run-time dispatch
(`c/blake3_dispatch.c:168-300`): the dispatcher picks a kernel from what the
CPU reports, so a kernel object must not contain instructions its own name does
not promise. One global CPU feature set — raise the library to AVX-512 and
every kernel compiles — would compile *and* run AVX-512 code on a CPU the
dispatcher had just decided did not have it. That is a worse bug than the one
the fix removes.

**Bound to.** Zig's C compilation model: the instruction set comes from the
resolved target, not from a flag, and a host target that happens to be wide is
not evidence about a baseline target. The narrower part is `std.Target.x86`'s
feature table and `std.zig.system.resolveTargetQuery` as Zig 0.16 spells them.

**Status.** `OBSERVED` — both x86 targets compile, four kernel objects each, the
core at baseline: `local://foundation-expansion-blake3-isa-target-x86_64-linux-gnu-114.log`
and `-isa-target-x86_64-windows-gnu-115.log`, 14/14 steps each.

---

## 10. A gate that compares this build with itself proves nothing

**Condition.** The C-surface gate in `verify.yml` compiled a program against the
installed header and archive and then checked it two ways that cannot fail for
the reason anyone cares about: comparing the version string the linked library
reported against a pinned constant, and comparing two calls into this same
build against each other.

**Symptom.** Not a compiler error — a design fault, found by reading. Both
checks pass for a library that is consistently wrong: a build reporting the
wrong version, or one whose every mode is off by the same amount, clears both.
`AGENTS.md` §7 says the same about permanent tests.

**Decision.** The version is printed by `smoke.zig` and never compared, and
every answer the C gate checks is copied out of upstream's published
`test_vectors/test_vectors.json`: the `key` and `context_string` fields, and the
complete 131-byte extended outputs of the `input_len` 0 and `input_len` 3 cases
in all three modes. It calls every hasher routine the header declares except
the oneTBB entry this build never defines, so a declaration whose type is wrong
fails to compile and one the archive does not define fails to link; then it
exercises segmented updates (including a zero-length one),
`blake3_hasher_finalize_seek` at offset 65 — one byte into the second 64-byte
block, so the returned window begins inside a block it does not begin — and
`blake3_hasher_reset` after two whole chunks plus a byte of poison, in each of
the three modes. Both context spellings are held to the same published
derive-key answer. Upstream publishes no NUL-bearing context, so there is no
published answer for one; that behaviour stays where it can be falsified, in
the Zig suite, which compares such a context against its own truncation.

**Status.** `SOURCE-CONFIRMED` for the change (read out of `verify.yml`),
`OBSERVED` for the run: installed into a scratch prefix outside the tree
(`local://foundation-expansion-blake3-installed-artifact-gruenau8-187.log`),
then compiled against the installed `blake3.h`, linked against the installed
`libblake3.a` and run — exit 0, `public C surface compiled, linked and ran`
(`…-installed-C-surface-190.log`).

---

## 11. Two tests that only mean something at the size they were made

**Decision.** `tests.zig` poisons with `2 * chunk_len + 1` bytes (2049) before
`reset`, in all three modes, and its sixth test compares the facade's
length-passing derive-key context with upstream's `const char *` entry point.

*Why the poison is that long.* A `Hasher` keeps a chaining-value stack
(`c/blake3.h:51-61`) and `hasher_push_cv` pushes one chaining value per
completed chunk (`c/blake3.c:468-474`). A poison shorter than one chunk never
completes a chunk, so the stack is empty when `reset` runs and a reset that
cleared only the block buffer would still agree with the published answer. Two
chunks and a byte is the shortest poison that leaves two chaining values live.

*Why the prefix comparison rather than a published answer.* Upstream publishes
no context containing a NUL, so there is no published digest to hold such a
context to. What is falsifiable is the difference: the length-taking entry
point and the C-string entry point must agree on the published context, and
must disagree on the same context with a byte appended after a NUL — and two
distinct NUL-bearing contexts must differ from each other, which a wrapper
passing the context as a C string cannot manage.

**Status.** `OBSERVED` — `zig build test` in Debug and in ReleaseSafe and with
`-Dportable=true` each report 6/6 against this file
(`local://foundation-cross-test-stable-blake3-native-Debug.log`,
`…-native-ReleaseSafe.log`, `local://foundation-expansion-blake3-isa-portable-debug-130.log`;
the portable row is the 2026-10-01 receipt and has not been re-run since). The
earlier green receipts predate both changes and are superseded; the current
table in `README.zig.md` names the current ones. The 20 platforms in the full
matrix that executed this suite report `6/6` each as well
(`local://foundation-cross-test-corrected-blake3-<target>.log`).

---

## 12. What the 32-bit and big-endian platforms in the full matrix depend on

**Condition.** `zig build check` covers six targets
(`build.zig`, `check_targets`), all of them 64-bit except `wasm32-wasi`. When
this entry was written the full `cross-test` matrix named platforms no gate had
compiled this package for: `x86-linux`, `x86-netbsd`, `x86-openbsd`,
`x86-windows`, `arm`, `armeb`, `thumb`, `thumbeb`, `hexagon`, `riscv32`,
`mips`, `mips64`, `powerpc`, `powerpc64`, `s390x` and the two big-endian AArch64
rows. The kernel selection in `add_c_library` is the one place where a wrong
answer is a *compile* error rather than a wrong digest, so it was read against
upstream's own rules before any of those platforms was compiled. The status at
the end of this entry is what the matrix later observed.

**Findings — `SOURCE-CONFIRMED`, read out of source, not executed.**

* *Big endian is already handled by the arch tag, not by a check that is
  missing.* Zig 0.16.0 gives every big-endian family its own `Cpu.Arch` value —
  `Arch.endian()` lists `.aarch64_be`, `.armeb`, `.thumbeb`, `.mips`, `.mips64`,
  `.powerpc`, `.powerpc64` and `.s390x` separately from their little-endian
  twins (`lib/std/Target.zig:1648-1700`). `Simd.for_arch` matches on
  `std.Target.Cpu.Arch`, so `cpu.arch == .aarch64` is *little-endian AArch64
  only* and `aarch64_be-linux` and `aarch64_be-netbsd` fall through to `.none`.
  That is what has to happen: `c/blake3_neon.c:4-9` is
  `#ifdef __ARM_BIG_ENDIAN` / `#error "This implementation only supports
  little-endian ARM."`, so a build that selected `.neon` for a big-endian
  AArch64 target would fail to compile rather than hash wrongly. Upstream
  reaches the same conclusion a different way, in `c/blake3_impl.h:61-72`, which
  autodetects `BLAKE3_USE_NEON 0` under `__ARM_BIG_ENDIAN`; this build passes
  `-DBLAKE3_USE_NEON=1` explicitly for `.aarch64`
  (`build.zig`, `add_c_library`), which overrides that autodetection — and the
  override is harmless precisely because `.aarch64_be` never reaches it. **A
  future edit that switches this selection to `arch.family()` or to an
  endianness-blind name would break those two rows.**
* *32-bit x86 is upstream's own rule, including the AVX-512 kernel.*
  `c/CMakeLists.txt:31` sets `BLAKE3_X86_NAMES` to `i686 x86 X86`, `:106-114`
  selects `x86-intrinsics` for that list, and `:181-199` adds **all four**
  intrinsics sources — `blake3_avx2.c`, `blake3_avx512.c`, `blake3_sse2.c`,
  `blake3_sse41.c` — at `-mavx512f -mavx512vl` among the flags. Building the
  AVX-512 kernel for 32-bit x86 is upstream's recipe, not an extension here.
  `c/blake3_dispatch.c:60-75` carries a dedicated `__i386__` inline-assembly
  branch for `cpuid`/`cpuidex`, so the run-time dispatch is written for it too.
* *A kernel still cannot inherit more than its own instruction set on 32-bit.*
  `kernel_target` pins `cpu_model = .baseline`, sets `cpu_features_add` to
  exactly the row's feature set and empties `cpu_features_sub`; the compiler's
  own resolver then adds `.@"32bit_mode"` for `.x86` and populates feature
  dependencies (`lib/std/zig/system.zig:396-417`). So the SSE2 object cannot
  pick up SSE4.1 from a baseline model that happens to have it, on either
  pointer width.
* *The core is byte-order independent.* `c/blake3_impl.h:152-186` assembles and
  stores 32-bit words one byte at a time (`load32`, `store32`,
  `load_key_words`, `load_block_words`), so `blake3_portable.c` and the x86
  kernels agree on a big-endian target. A grep for `_Static_assert`,
  `__int128`, `sizeof(void *)`, `sizeof(long)` and `uintptr_t` across
  `c/blake3.c`, `c/blake3_impl.h`, `c/blake3_portable.c`, `c/blake3_dispatch.c`
  and `c/blake3.h` returns nothing: there is no width assumption to break.
* *The ARM dispatch probes nothing.* `c/blake3_dispatch.c:113-167` returns 0 in
  the non-x86 branch, and `:291-295` and `:328-331` select the NEON kernel from
  `BLAKE3_USE_NEON == 1` at compile time. There is no `getauxval`, no
  `sysctlbyname` and no OS branch, so no libc or kernel probe can fail on
  NetBSD, OpenBSD, FreeBSD, macOS, Catalyst or Windows.
* *32-bit ARM deliberately does not take NEON, which is a divergence from
  upstream's CMake and a load-bearing one.* `c/CMakeLists.txt:116-121` picks
  `neon-intrinsics` for `BLAKE3_ARMv8_NAMES` — which includes `armv8` — when
  `-mfpu=neon` is defined, and `:83-85` defines that flag for a non-64-bit ARMv8
  processor. `c/blake3_neon.c` cannot serve that target: `:1-9` refuses
  big-endian outright and `:28-70` uses the aarch64 spellings
  (`vsriq_n_u32`, `vld1q_dup_u32`, `vreinterpretq_u32_u16(vrev32q_u16(...))`),
  which armv7 NEON does not provide. This build therefore gives `.arm`,
  `.thumb`, `.armeb` and `.thumbeb` the portable core with upstream's own
  "none" macros (`c/CMakeLists.txt:215-222`), which is upstream's documented
  answer for a target with no kernel (`c/README.md:376-383`). Recorded here as
  a decision, not as a silent omission.
* *The Zig side has nothing target-conditional in it.* `zig/root.zig` is
  arithmetic over caller-owned slices and a pass-through of `blake3_hasher`;
  `tests.zig` embeds the upstream vectors with `@embedFile` and compares
  hexadecimal bytes, so the suite reads no file at run time and holds on every
  platform the same way. No test was added, removed or re-pinned for any of the
  above: there is no new observable behaviour to pin, only a build-time
  selection that was already right.

**Status.** `SOURCE-CONFIRMED` when written, and every prediction in it now has
an observed compile beside it. `cross-test` (entry 14 of `CHANGELOG.md`) built
all 53 platforms and ran this package's six tests on 20 of them: `x86-linux`
compiled all four intrinsics kernels including AVX-512 and passed 6/6;
`aarch64_be-linux` and `aarch64_be-netbsd` compiled `blake3: portable core
only`, so neither reached `c/blake3_neon.c`; `arm-linux`, `thumb-linux`,
`thumbeb-linux`, `riscv32-linux`, `hexagon-linux`, `s390x-linux` and
`powerpc-linux` likewise took the portable core. Each target's own log is
`local://foundation-cross-test-corrected-blake3-<target>.log`, and the
per-target record is `local://foundation-cross-test-corrected-blake3.json`.
What the matrix did **not** do is execute a test binary on any of the 33
platforms with no runner here: those are `build_only`, so the compile is
observed and the behaviour on them is not.

**Targets bound.** Zig 0.16.0's `Cpu.Arch` tag set; BLAKE3 1.8.7
(`f3149ec5bb5449af877ba20377a11008ff499fa2`). Both are re-read, not recalled,
before any of this is relied on again.

---

## 13. A per-test deadline is not a per-build deadline, and emulation is the reason

**Condition.** `cross-test` set one deadline for a target's whole compile-plus-run
(`CROSS_BUILD_TIMEOUT`) and left the other at the harness default
(`CROSS_TIMEOUT`, 300 seconds). That default is generous for a native run of
this suite: the same six tests finish in `189ms` in Debug and `35ms` in
ReleaseSafe (`local://foundation-cross-test-stable-blake3-native-Debug.log`,
`…-ReleaseSafe.log`).

**Symptom.** The first full matrix was 18 pass, 33 `build_only`, 2 fail — and the
two failures were `aarch64-linux` and `aarch64_be-linux`, both exit 1, both red
on a deadline rather than on an answer:

```
error: 'tests.test.streaming is invariant to how the input is split at block and chunk boundaries' timed out after 5m368.911ms
Build Summary: 4/6 steps succeeded (1 failed); 5/6 tests passed (1 timed out)
```

(`local://foundation-cross-test-matrix-blake3-aarch64-linux.log`, and
`…-aarch64_be-linux.log` with two timeouts, `5m248.837ms` and `5m112.063ms`.)
Both targets compiled; the tests that finished were the ordinary comparisons
against upstream's published vectors and they passed.

**Cause.** Two independent clocks were being confused. `CROSS_BUILD_TIMEOUT`
bounds a whole target and said nothing about one test case; the 300-second
default bounded each test case and was never wide enough for a Debug AArch64
build replaying 35 published vectors — inputs to 102400 bytes, all three modes,
complete 131-byte extended outputs — through QEMU-user. Raising only the
per-target deadline would not have helped; raising only the per-test one leaves
no room for a slow compile either.

**Fix.** `CROSS_BUILD_TIMEOUT=3600` and `CROSS_TIMEOUT=1800`. No test was
shortened, dropped, re-pinned or given a smaller vector set, no mode was removed,
and the profile still names no target list and passes no `-D` option.
`cross-test --list` and `cross-test --no-profile --list` print the same 53
platforms, so nothing was quietly narrowed to make the run finish.

**Status.** `OBSERVED` — the corrected run `20261002-055258-61044-19309` built
all 53 with exit 0, ran the six tests 6/6 on 20 of them, recorded 33
`build_only`, and failed none; the two AArch64 rows report
`run test blake3-tests 6 pass (6 total) 1m`
(`local://foundation-cross-test-corrected-blake3.json`, and one
`local://foundation-cross-test-corrected-blake3-<target>.log` per target). The
first run's timeout receipts are kept: they are the observation that produced
the fix, not a claim about the current tree.

**Bound to.** This suite's vector set under emulation, not to BLAKE3 and not to
any compiler: a fork whose published vectors were an order of magnitude smaller
would not have needed this, and a slower runner than this host's QEMU would need
the per-test number raised again. `CHANGELOG.md` entry 15.

**Targets bound.** The `cross-test` harness's two deadline settings; BLAKE3
1.8.7's 35-case `test_vectors/test_vectors.json`; QEMU-user `aarch64` and
`aarch64_be` on this host.

## 14. Relocating a file relocates the integrity record, not the bytes

**Condition.** `README.md` was upstream's own README, byte for byte, and the
integrity record named it at that path. Giving the fork its own README under
that name moves the upstream bytes to a new path — while the digest of those
bytes does not move at all.

**Symptom.** None observed. This is the trap: nothing fails, and the failure
mode is silent. A record left naming `README.md` would report the fork's own
prose as upstream's pinned bytes, and would fail the first time anyone ran
`sha256sum -c UPSTREAM.sha256`.

**Fix.** The record names `README.upstream.md` with the identical digest
`37eb920117b5b75d2079862e1de630b892c5b0428abe6190eaf55778b0630826`. Every
citation of upstream's README prose names the preserved path; the line numbers
are unchanged precisely because the bytes are unchanged. The header comment says
why `README.md` is absent, so the next reader does not add it back.

**Status.** `PENDING-VERIFICATION` — the relocation is a path change, but
`sha256sum -c UPSTREAM.sha256` has not been re-run against the current tree.

**Bound to.** Any integrity record written as `<digest>  <path>` lines. It is
not bound to BLAKE3 and not to Markdown.

## 15. An absent lock file is a missing receipt, not a licence to invent one

**Condition.** A flake that names a `nixpkgs` input and carries no `flake.lock`.

**Symptom.** None observed. The temptation is the failure: a narHash typed from
memory, or copied from an unrelated project, looks like completeness and is
indistinguishable from a fabrication once it is in the tree.

**Fix.** `flake.nix` declares the pinned input URL and carries no lock;
`devenv.yaml` pins its revision explicitly so a clean checkout resolves
deterministically without reading a lock. Both lock files are named in the
documentation as the driver's to generate from an observed evaluation. The same
rule covers the source filter: it names no hash, no store path and no host path,
because `src = ../.` is this repository's own tree and needs no fixed-output
derivation at all.

**Status.** `SOURCE-CONFIRMED` — read out of the three files as written. Neither
was evaluated.

**Bound to.** nixpkgs revisions this workspace has observed; a different pin is a
different claim and needs its own evaluation.

## 16. A package-level licence label cannot express a three-way choice

**Condition.** Upstream offers CC0 1.0, Apache 2.0, or Apache 2.0 with the LLVM
exceptions. `meta.license` takes exactly one SPDX identifier.

**Symptom.** None observed. The failure is a false statement: picking one branch
silently and recording it as `license` reads as "this package is licensed under
X" when the repository is licensed under "X or Y or Z".

**Fix.** `meta.license` names one branch with an adjacent comment stating that it
records only the branch this output is distributed under, that it narrows
nothing, and that `FORK-LICENSE.md` and `NOTICE.md` hold the actual choice. The
SPDX identifier for the fork's own source and build files is the whole
expression, which a per-file header *can* express and a `meta` attribute cannot.

**Bound to.** Any upstream whose licence is a disjunction. An upstream under a
single licence would not have hit this.

## 17. What has not been observed in this migration

Recorded so a later reader does not mistake silence for a result — and kept
current as those silences fill in. Every gate this migration touched is listed
with its state in `README.md` § "Build / run / test matrix" and in
`README.zig.md` § "Verification status"; where a row there still reads
`PENDING-VERIFICATION`, that table is the record and this section is not a
second copy of it.

Two of the items this entry was written with have since closed against this tree,
and one has not. A shared object **has** been produced: all four optimize modes
of `20261004T233628757747Z-69351` built and installed it, and the loader opened
that exact `libblake3.so.0.1.8` in all eight `-Druntime=true` cells of
`20261004T232823091897Z-23133`. The symbol-table and relocation inspection it
owes still has not been run. A runtime-loaded consumer **has** been built and
run — this tree's own provider, loaded by explicit path, six of six published
vectors in every cell, four optimize modes and both linkages. What has *not* been
run is the independent half of that route: no external provider was accepted for
this SDK, and in `20261004T232439Z` every route carries
`counts_as_external_coverage: false`, the one success being the own provider.

Still unobserved, and still silent for the same reason: neither Nix derivation
has been evaluated or built, no devenv shell has been entered, no `consumer/` or
installed-C program has been built against one of those cohorts' prefixes, the
`runtime-test` lifecycle suite and all three misuse modes have not been executed,
and the integrity record has not been re-run since the README relocation.

The runtime route's boundary is stated rather than measured. Symbol resolution,
a `blake3_version()` string and a release text are **not** ABI proof — the ABI
claim rests on the translated `blake3.h` and on the provider having been compiled
with the same `BLAKE3_MAX_DEPTH`, `BLAKE3_BLOCK_LEN`, `BLAKE3_OUT_LEN`,
`BLAKE3_KEY_LEN` configuration. That is a reading of the source, and no
cross-configuration provider has been attempted — nor has a provider this tree
did not build.

## 18. An assertion the build API cannot express must not be written down as a gate

**Condition.** `runtime/misuse.zig` has three modes. `after-load <provider>`
must *succeed*; `pre-load` and `linked-load` must *stop* — the call arrived
before any load, and the message must name the library, the function and the way
out. All three are worth gating, and a gate table that quietly covered only one
of them would read as though all three were covered.

**Symptom.** None observed. The trap is a plausible-looking gate: `Step.Run` in
this Zig release exposes `expectExitCode(u8)` (`Run.zig:628-631`) and nothing
for "must not exit zero". Writing `expectExitCode(1)` would be inventing an exit
code nothing has run and calling it an expectation.

**Fix.** The `runtime-misuse` step runs `after-load <provider>` only, with
`expectExitCode(0)` — the assertion the API can actually carry. `pre-load` and
`linked-load` are compiled in every configuration and every optimize mode, and
are **driver-run and driver-observed**; the tables in `README.md` and
`README.zig.md` list them as a separate row from the control rather than folding
them into it. `zig build check -Druntime=true` does compile both programs for
all six matrix targets, because `add_target_check` builds through the same
`add_graph`.

The neighbouring limit is the same shape: `BLAKE3_TEST_PROVIDER` and
`BLAKE3_TEST_ALIEN` are read from the caller's environment because `Step.Run`
takes only literal strings in an environment map (`Run.zig:595-598`) — there is
no API for a build-time-resolved path there. So the build inherits them rather
than synthesising them, and `load_tests.zig` fails loudly when one is missing,
which is what its own header specifies. Writing a skip-when-absent path would
have been the fake fallback.

**Bound to.** `std.Build.Step.Run`'s current surface. A release that grows an
expectation for a non-zero exit would let these three modes become ordinary
gates, and this note should be revisited then.

## 19. A build comment and the code it describes disagreed

**Condition.** Writing the linkage documentation required answering one
question — is `-fvisibility=hidden` applied to the static build too? — and the
build answered it twice, differently.

**Symptom.** None observed; no gate has run. `build.zig:344-349` says the flag
"is applied to the static build as well, because upstream applies it there too
(`c/CMakeLists.txt:150-155` sets it unconditionally, not under
`BUILD_SHARED_LIBS`) and because a hidden symbol in an archive is still
linkable". `cUnitFlags` at `build.zig:359-361` returns `c_flags_shared_flags` when
`linkage == .dynamic` and plain `c_flags` otherwise, and
`c_flags_shared_flags` is `c_flags ++ c_flags_shared`
(`build.zig:370`) — so the code applies it to the shared delivery only. One of
the two is wrong.
**Decision.** Settled in favour of the **code**: `-fvisibility=hidden` reaches
the shared delivery only, and `build.zig:343-362` now says so. The comment was
the thing that changed. `cUnitFlags` (`build.zig:359-361`) was already correct;
what was wrong was the prose above it.

*Why the code and not the comment.* Upstream sets `C_VISIBILITY_PRESET hidden`
unconditionally (`c/CMakeLists.txt:150-155`), so upstream's own static archive
does carry the flag, and "match upstream exactly" is a real argument for the
other resolution. It was not chosen because of the cost side: `static` is the
delivery every gate in this repository's recorded history observed, and adding
a flag to that command line perturbs a verified build for a property that is
inert there — visibility governs a dynamic symbol table and an archive has
none, so a hidden symbol in an archive is still linkable. The flag only does
work where there is a table to narrow, which is exactly the shared object. The
deviation is therefore confined to an inert property of the static artifact
while the artifact that actually has an export surface matches upstream exactly.

*What was wrong in the first report.* The build owner's handoff to this role
stated that the flag "now also applies to the STATIC build" and listed that as a
risk to a previously-green command line. The code never did that, so the risk
did not exist and has been struck from every document here. The accurate
statement is the reverse: the static build's C command line is unchanged from
before `-Dlinkage` existed, and the shared build is the one carrying the flag.

**Why it blocks nothing.** Both original resolutions left the static build's
link behaviour unchanged, so this was never a defect that could produce a wrong
artifact — it was a record asserting something untrue, which is the same class
as entries 14 to 18 and for the same reason. The thing that genuinely would
bite is a *different* one and is not in doubt: a kernel object compiled with
default visibility would export `blake3_compress_in_place_sse41` from a shared
object, which is why every C translation unit goes through the single
`cUnitFlags` function (`build.zig:829`, `build.zig:889`).

**Bound to.** One deliberate deviation from upstream's `C_VISIBILITY_PRESET`, on
the static delivery, and to the reasoning that a build's recorded history should
not be perturbed for an inert property. If a future gate ever *does* observe a
difference between this static archive and upstream's, this entry is where the
question belongs — not the flag's presence on the command line, which is now
