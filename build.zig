//! Zig 0.16 build for the BLAKE3 C library.
//!
//! The library is upstream's own C, byte for byte: `c/blake3.c`,
//! `c/blake3_dispatch.c`, `c/blake3_portable.c` and, for the target being
//! built, the one SIMD flavour that target has. Nothing is downloaded, no
//! CMake/Make/configure script is executed, and the default mode compiles
//! everything from this repository rather than linking an installed copy.
//!
//! Upstream reference: tag `1.8.7`, `c/blake3.h:33`
//! (`BLAKE3_VERSION_STRING "1.8.7"`) and `c/CMakeLists.txt:13`
//! (`project(libblake3 VERSION 1.8.7 ...)`). The pinned commit SHA belongs in
//! `FORK-NOTES.md` and `UPSTREAM.md`, which the fork's provenance owner
//! writes from `git log`; this script does not restate a SHA it cannot read.
//!
//! Entry points
//! -----------
//!   zig build           install the compiled C library and its public header,
//!                       and compile the example program
//!   zig build test      run the behavioural tests for the selected target
//!                       (`-Dtarget`; the host when it is absent)
//!   zig build smoke     run the example program
//!   zig build check     compile the C core, the facade, `tests.zig` and
//!                       `smoke.zig` for the six-target matrix, running
//!                       nothing
//!
//!   cross-test       the same `test` step, for the published 53-platform
//!                   Zig 0.16.0 Tier 1/2 table rather than the host alone.
//!                   `cross-test` discovers `cross-test.profile.sh` from the
//!                   package root, runs `zig build test -Dtarget=TARGET` for
//!                   each of them, and executes the binary where a runner
//!                   exists and records explicit `build_only` coverage where
//!                   one does not. `test` is what the harness reaches for, and
//!                   it builds the same graph and the same test binary for
//!                   whatever `-Dtarget` says: nothing in `build()` narrows
//!                   the graph to the host, and the `check` matrix below is
//!                   compile-only and is not a substitute for it.
//!
//! Options
//! -------
//!   -Dportable=true    compile the scalar core only, for every target: the
//!                      same facade, the same test vectors, no SIMD kernel.
//!                      Upstream's own portable recipe is
//!                      `-DBLAKE3_NO_SSE2 -DBLAKE3_NO_SSE41 -DBLAKE3_NO_AVX2
//!                      -DBLAKE3_NO_AVX512` (`c/README.md:336-342`). It exists
//!                      so the official vectors can be gated twice, once
//!                      through the dispatched kernels and once through
//!                      `blake3_portable.c` alone, and because a mismatch
//!                      between those two paths is a real upstream bug class.
//!                      No effect in system mode, where no C is compiled here.
//!   -Dsystem=true      link an installed `libblake3` instead of compiling
//!                      `c/`, and translate the installed `blake3.h` instead
//!                      of the bundled one. See the note on
//!                      `systemIntegrationOption` below.
//!   -Dtarget=<triple>  build for one target; `zig build check` then checks
//!                      that target only instead of the whole matrix.
//!
//! System-library mode
//! -------------------
//! `systemIntegrationOption("blake3", ...)` is the switch, and it is the only
//! authority: when the build runner decides the mode (`-fsys=blake3` on a
//! runner that feeds that map, and `-Dsystem=true` here, which supplies the
//! option's default on a stock Zig 0.16.0 runner, where nothing else fills
//! `std.Build.Graph.system_library_options`), the two agree and the mode is
//! the same either way. `-Dsystem=true` is declared with `b.option` for
//! exactly that reason and is not a second code path: the branch below reads
//! only the `systemIntegrationOption` result.
//!
//! The mode is real: it links `-lblake3` (`b.systemIntegrationOption`'s
//! package name matches the real Debian/Ubuntu/Fedora library, which ships
//! `blake3.h` and `libblake3.so` beside a `libblake3.pc`) and it translates
//! the *installed* header, because `zig/translate.h` resolves `<blake3.h>`
//! through the include path this build gives the translation, and the system
//! mode is the one that does not add `c/` to it. Translating the bundled
//! 1.8.7 header against an older installed library would describe an ABI that
//! may not be the one on disk (`WISDOM.md` W14).

const std = @import("std");

/// Package id, published module name, and name of the C artifact.
const lib_name = "blake3";

/// The Zig facade: a thin, allocation-free wrapper over the translated
/// `blake3_hasher_*` calls. It re-exports the translated module as `c`.
const facade_source = "zig/root.zig";

/// The one header this package translates. It is a fork-authored wrapper
/// whose whole job is to name the header the selected library was declared
/// with; see the file for why it is a wrapper and not a copy.
const translate_header = "zig/translate.h";

/// Test root. Every public facade method is called from here, which is what
/// makes `zig build check` a real check of the facade: Zig analyses a
/// function body only when something calls it.
const test_source = "tests.zig";

/// The deterministic example program that `zig build smoke` runs.
const example_source = "smoke.zig";

/// Language level for every C translation unit.
///
/// Upstream asks for C99 with extensions off (`c/CMakeLists.txt:154,156`:
/// `C_EXTENSIONS OFF`, `c_std_99`). `gnu11` satisfies that floor and is
/// pinned rather than inherited: `c/blake3_dispatch.c:21-31` turns on the C11
/// atomics path whenever `__has_include(<stdatomic.h>)` succeeds, which is
/// true of every compiler here, so compiling in a C11 mode keeps
/// `_Atomic int g_cpu_features` (`c/blake3_dispatch.c:34`) on its native
/// spelling instead of on a compiler extension of a C99 mode. Nothing else
/// depends on the level, and pinning it means a change of clang default
/// cannot silently move it.
const c_flags = [_][]const u8{"-std=gnu11"};

/// The core library, upstream's own `add_library(blake3 ...)` list
/// (`c/CMakeLists.txt:130-134`). These three files are the whole library on
/// every target; everything below adds acceleration, never replaces the core.
const core_sources = [_][]const u8{
    "c/blake3.c",
    "c/blake3_dispatch.c",
    "c/blake3_portable.c",
};

// Files in `c/` this build deliberately does not compile, and why:
//
//   * `c/main.c` and `c/test.py` are upstream's C test harness. `test.py`
//     calls internal functions such as `get_cpu_features`, which
//     `c/blake3_dispatch.c:105-113` makes `static` unless the library is
//     built with `BLAKE3_TESTING`. Compiling it would mean building a second,
//     differently configured copy of the library whose only purpose is to
//     re-run upstream's own tests; the Zig tests in `tests.zig` cover the same
//     ground against upstream's own vectors.
//   * `c/example.c`, `c/blake3_tbb.cpp` and `c/example_tbb.c`: the examples
//     are programs, not library sources, and the TBB ones additionally need a
//     C++20 toolchain and oneTBB.
//   * the twelve `.S` and `.asm` files: see the note on `x86_kernels`.

/// What upstream calls the "none" configuration
/// (`c/CMakeLists.txt:215-222`): the macros that tell `blake3_impl.h` and
/// `blake3_dispatch.c` that no accelerated kernel is linked in, so every
/// dispatch site falls through to the portable one.
///
/// This is used for a target with no upstream SIMD implementation (riscv64,
/// wasm32) and for `-Dportable=true` on any target. It is the same recipe in
/// both cases because it is the same thing: three core sources, no kernels.
const no_simd_macros = [_][2][]const u8{
    .{ "BLAKE3_USE_NEON", "0" },
    .{ "BLAKE3_NO_SSE2", "1" },
    .{ "BLAKE3_NO_SSE41", "1" },
    .{ "BLAKE3_NO_AVX2", "1" },
    .{ "BLAKE3_NO_AVX512", "1" },
};

const X86Kernel = struct {
    /// The instruction set's own name. It names that kernel's object file,
    /// so `--summary all` shows which of the four instruction sets was
    /// compiled, for which target, instead of four steps with one name.
    name: []const u8,
    /// The upstream intrinsics translation unit for one instruction set.
    source: []const u8,
    /// The CPU features this translation unit is written in: the instruction
    /// set, and the only instruction set it is compiled for. Upstream's `-m`
    /// flag for each of these is named in the table below and is not passed
    /// on the command line, because Zig takes the instruction set from a
    /// module's resolved target rather than from a `-m` flag; `WISDOM.md` W20
    /// is this workspace's account of the difference, and `add_x86_kernel`
    /// says what depends on it.
    features: []const std.Target.x86.Feature,
};

/// The four x86 kernels, as upstream's C intrinsics flavour, one instruction
/// set each. The recipe is upstream's (`c/CMakeLists.txt:190-199`, and the
/// same one in `c/Makefile.testing:52-62` and `c/README.md:320-326`); the
/// instruction set reaches the compiler as a target feature rather than as
/// the `-m` flag that recipe spells, and the table says which is which.
///
/// Why the intrinsics flavour and not upstream's default hand-written
/// assembly, which upstream prefers for x86_64 (`c/README.md:299-304`):
///
///   * Both flavours are the same five instruction sets. `c/README.md:295-296`
///     says the library "expects to be linked with code for five different
///     instruction sets: portable C, SSE2, SSE4.1, AVX2, and AVX-512", and
///     `c/blake3_dispatch.c:168-300` dispatches on the CPU at run time, so a
///     host with AVX-512 still executes the AVX-512 kernel. Nothing is
///     downgraded by choosing intrinsics; only the object file behind each
///     kernel differs, and upstream ships both.
///   * The assembly route needs a different source file per platform
///     (`c/CMakeLists.txt:49-79`: unix, windows-gnu, windows-msvc) and a
///     working target assembler for each of the six matrix targets. The
///     intrinsics route is four C files and one feature set each, compiled by
///     the same clang that compiles everything else in this build.
///   * They must never be combined: each flavour defines
///     `blake3_compress_in_place_sse41` and the rest, so compiling both is a
///     duplicate-symbol link failure. `c/README.md:298-304` offers them as
///     alternatives, one per instruction set, and this build picks exactly
///     one scheme for the whole library.
///
/// One kernel, one object, one resolved target. Every row below is compiled
/// by `add_x86_kernel` into an object of its own, against a target pinned to
/// the baseline CPU model with that row's features and nothing else switched
/// on. That is upstream's shape: one library per instruction set, here one
/// object per instruction set. It is also the only shape in which the
/// run-time dispatch can be believed, because a kernel object compiled for
/// more than its own instruction set would execute those instructions on
/// exactly the CPU the dispatcher chose it for not having them.
const x86_kernels = [_]X86Kernel{
    // Upstream compiles this one with `-msse2`.
    .{ .name = "sse2", .source = "c/blake3_sse2.c", .features = &.{.sse2} },
    // Upstream: `-msse4.1`. `.ssse3` and `.sse3` arrive with it as
    // dependencies, and this file needs them: `c/blake3_sse41.c:31,40` calls
    // `_mm_shuffle_epi8`, which is SSSE3.
    .{ .name = "sse41", .source = "c/blake3_sse41.c", .features = &.{.sse4_1} },
    // Upstream: `-mavx2`. `.avx` arrives with it, and this file cannot be
    // compiled without it: an `__m256i` passed or returned by value changes
    // the ABI when `.avx` is off, which is what the baseline x86_64 cross
    // compile reported from `c/blake3_avx2.c:236`.
    .{ .name = "avx2", .source = "c/blake3_avx2.c", .features = &.{.avx2} },
    // Upstream: `-mavx512f -mavx512vl`, and `c/README.md:329-330` says both
    // are required for GCC and Clang. Two separate CPU bits, neither implied
    // by the other, hence two entries: `c/blake3_avx512.c:1227` returns
    // through `_mm256_mask_storeu_epi32`, which is AVX512VL.
    .{
        .name = "avx512",
        .source = "c/blake3_avx512.c",
        .features = &.{ .avx512f, .avx512vl },
    },
};

/// The AArch64 NEON kernel. `c/blake3_impl.h:61-72` already autodetects it
/// for little-endian AArch64; `-DBLAKE3_USE_NEON=1` is passed anyway, because
/// that is what upstream's own `neon-intrinsics` branch passes
/// (`c/CMakeLists.txt:204-209`) and it makes the selection an explicit fact
/// of this build rather than a consequence of a compiler predefine. No extra
/// flag is needed: NEON is baseline for AArch64, and the extra `-mfpu=neon`
/// upstream mentions (`c/README.md:364-374`) is a 32-bit ARM concern.
const NeonKernel = struct {
    source: []const u8,
    macro: [2][]const u8,
};

const neon_kernel: NeonKernel = .{
    .source = "c/blake3_neon.c",
    .macro = .{ "BLAKE3_USE_NEON", "1" },
};

/// Which accelerated kernels a target gets.
const Simd = enum {
    /// The four x86 intrinsics kernels, dispatched at run time.
    x86_intrinsics,
    /// `c/blake3_neon.c`, dispatched by `c/blake3_dispatch.c:291-295`.
    neon,
    /// No kernel: the core alone, with upstream's "none" macros.
    none,

    fn for_arch(arch: std.Target.Cpu.Arch, portable: bool) Simd {
        if (portable) return .none;
        return switch (arch) {
            // 32-bit x86 takes the intrinsics too, and that is upstream's own
            // rule: `c/CMakeLists.txt:106-114` picks `x86-intrinsics` for
            // 32-bit x86 because the assembly files are x86_64-only
            // (`c/README.md:302-304`).
            .x86_64, .x86 => .x86_intrinsics,
            .aarch64 => .neon,
            // riscv64 and wasm32 have no upstream implementation: the
            // portable core is upstream's documented answer for "Other
            // Platforms" (`c/README.md:376-383`).
            else => .none,
        };
    }

    fn kind(simd: Simd) []const u8 {
        return switch (simd) {
            .x86_intrinsics => "x86 intrinsics (SSE2, SSE4.1, AVX2, AVX-512)",
            .neon => "AArch64 NEON",
            .none => "portable core only",
        };
    }
};

/// Which libblake3 the package links.
const Library = enum {
    /// Compiled from the pinned upstream C in `c/`.
    bundled,
    /// The installed library `systemIntegrationOption("blake3")` selected.
    system,
};

/// The cross-compilation matrix `check` walks when no target is named. The
/// order is the one the workspace uses everywhere; nothing is skipped, and
/// nothing here is pre-judged: if a target cannot be satisfied on the machine
/// running the gate, that is for the gate to report.
const check_targets = [_]std.Target.Query{
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .macos, .abi = .none },
    .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
    .{ .cpu_arch = .riscv64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .wasm32, .os_tag = .wasi },
};

/// One target's library and facade.
const Graph = struct {
    /// The compiled C library, or null in system mode, where nothing is
    /// compiled from this tree.
    c_lib: ?*std.Build.Step.Compile,
    /// The facade, with `c` bound to the translated aggregate header.
    module: *std.Build.Module,
};

/// The name a compiled artifact carries in this build graph.
///
/// The published graph installs `libblake3.a`, the name a C consumer's
/// `-lblake3` needs. A check graph installs nothing, so its artifacts carry
/// the target triple instead: six targets share one build graph, and six
/// steps all called "blake3" make `--summary all` impossible to read.
fn artifact_name(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    public: bool,
) []const u8 {
    if (public) return lib_name;
    const triple = target.result.zigTriple(b.allocator) catch @panic("unspellable target");
    return b.fmt("{s}-{s}", .{ lib_name, triple });
}

/// Builds one target's library and facade.
///
/// `public` chooses between the package module set, which is what a
/// dependent reaches through `dep.module("blake3")`, and a private module. A
/// cross-target check needs the private form: modules are registered by name
/// against the whole build, so registering `blake3` once per matrix target
/// would leave only the last of them reachable and silently stop checking the
/// rest.
fn add_graph(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    portable: bool,
    library: Library,
    public: bool,
) Graph {
    const c_lib: ?*std.Build.Step.Compile = if (library == .bundled)
        add_c_library(b, target, optimize, portable, artifact_name(b, target, public))
    else
        null;

    const translate = b.addTranslateC(.{
        .root_source_file = b.path(translate_header),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    if (library == .bundled) {
        // `zig/translate.h` includes `<blake3.h>`, and this is the only
        // header search path the translation has. Without it the translation
        // would silently bind to whatever `blake3.h` happens to be installed
        // on the build machine, describing that library's declarations
        // rather than the ones this build compiles (`WISDOM.md` W14).
        translate.addIncludePath(b.path("c"));
    }

    const module = if (public)
        b.addModule(lib_name, .{
            .root_source_file = b.path(facade_source),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        })
    else
        b.createModule(.{
            .root_source_file = b.path(facade_source),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
    module.addImport("c", if (public) translate.addModule("c") else translate.createModule());
    if (c_lib) |lib| {
        module.linkLibrary(lib);
    } else {
        // System mode. `linkSystemLibrary` with pkg-config enabled (the
        // default) asks `libblake3.pc` for its cflags and falls back to a
        // plain `-lblake3` when pkg-config cannot answer, so the mode works
        // on a system that ships the library without the `.pc` file.
        module.linkSystemLibrary(lib_name, .{});
    }

    return .{ .c_lib = c_lib, .module = module };
}

/// Resolves one kernel's target: the caller's target, CPU back at baseline.
///
/// The architecture, the OS and its version range, the ABI, the libc version
/// and the object format all come from the resolved target rather than from
/// the `-Dtarget` string, so none of them is re-detected here and none of
/// them can drift from what the caller asked for. The CPU is the one part
/// that changes: it is pinned to `cpu_model = .baseline` and given exactly
/// `features`, so a kernel is compiled for its own instruction set and
/// nothing else, however wide the caller's target is.
/// `std.zig.system.resolveTargetQuery` adds the prerequisites the
/// `std/Target/x86.zig` table declares, so `.sse4_1` arrives with `.ssse3`
/// and `.sse3`, and `.avx512vl` with `.avx512f`.
///
/// This is `WISDOM.md` W20's decision, made for htscodecs and carried over
/// here. The CPU model is pinned rather than left at the caller's because a
/// kernel object compiled for more than its own instruction set is a
/// dispatch bug waiting to happen: `c/blake3_dispatch.c` runs the SSE2
/// kernel on a CPU that reported no SSE4.1, and an SSE2 object that had been
/// compiled with AVX-512 available would run AVX-512 on it.
///
/// `base` has to outlive the build: `Query.fromTarget` keeps a pointer to the
/// CPU model it is given, and the module keeps the query it produces.
fn kernel_target(
    b: *std.Build,
    base: *const std.Target,
    features: []const std.Target.x86.Feature,
) std.Build.ResolvedTarget {
    var query = std.Target.Query.fromTarget(base);
    query.cpu_model = .baseline;
    query.cpu_features_add = std.Target.x86.featureSet(features);
    query.cpu_features_sub = .empty;
    return b.resolveTargetQuery(query);
}

/// Compiles one x86 kernel as its own object file and links it into `c_mod`.
///
/// The kernel cannot be one more `addCSourceFile` on the library's own
/// module. A Zig C compilation takes its instruction set from its module's
/// resolved target, which `std/Build/Module.zig:592-598` turns into the
/// `-target`/`-mcpu` pair on the command line, and a `-m` flag does not widen
/// a target that does not already carry the feature: with `-msse4.1` on the
/// command line, `c/blake3_sse41.c:31` still failed with `error:
/// always_inline function '_mm_shuffle_epi8' requires target feature 'ssse3',
/// but would be inlined into function 'rot16' that is compiled without
/// support for 'ssse3'`. Compiling this package for a baseline
/// `x86_64-linux-gnu` and for `x86_64-windows-gnu` that way failed with 114
/// and 54 errors, all of that shape, and the native gates passed only because
/// a build host already has all four instruction sets, so its native target
/// allowed them and the defect stayed hidden.
///
/// The library's own target is not raised. The core sources and
/// `c/blake3_dispatch.c` keep the caller's requested baseline, which is what
/// makes the run-time CPUID dispatch in `c/blake3_dispatch.c:168-300` mean
/// anything. Only this one translation unit gets a target of its own, and it
/// becomes an object of its own that the library archives beside its core
/// sources: the shape upstream's own per-instruction-set libraries have
/// (`c/CMakeLists.txt:190-199`).
///
/// The kernel keeps upstream's language level and no `-m` flag: the
/// instruction set travels in the target now, and the `-msse2`, `-msse4.1`,
/// `-mavx2`, `-mavx512f -mavx512vl` of upstream's own recipes are named
/// against their rows in `x86_kernels` instead of on the command line.
///
/// `optimize` and the object format are the caller's, and `pic` is left unset
/// on the kernel module exactly as it is on the core's, so the object is
/// compiled with the same default the library's own compilation uses.
///
/// `name` is the library's artifact name, so the object is named after it and
/// one matrix target does not produce sixteen steps called the same thing.
fn add_x86_kernel(
    b: *std.Build,
    c_mod: *std.Build.Module,
    base: *const std.Target,
    optimize: std.builtin.OptimizeMode,
    name: []const u8,
    kernel: X86Kernel,
) void {
    const kernel_mod = b.createModule(.{
        .target = kernel_target(b, base, kernel.features),
        .optimize = optimize,
        // libc, for the reason the core asks for it: every kernel's first
        // include is "blake3_impl.h", and `c/blake3_impl.h:4-8` includes
        // <assert.h>, <stdbool.h>, <stddef.h>, <stdint.h> and <string.h>.
        .link_libc = true,
    });
    // For the kernel's own quoted include of "blake3_impl.h", the same
    // include path `add_c_library` gives the core sources.
    kernel_mod.addIncludePath(b.path("c"));
    kernel_mod.addCSourceFile(.{
        .file = b.path(kernel.source),
        .flags = &c_flags,
    });
    c_mod.addObject(b.addObject(.{
        .name = b.fmt("{s}-{s}-obj", .{ name, kernel.name }),
        .root_module = kernel_mod,
    }));
}

/// Compiles the C library for one target: core sources plus the kernels that
/// target can use, and nothing else. The kernels arrive as objects of their
/// own rather than as further sources of this module, one object per
/// instruction set; `add_x86_kernel` says why.
///
/// `name` is the artifact name this graph installs or reports; see
/// `artifact_name`.
fn add_c_library(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    portable: bool,
    name: []const u8,
) *std.Build.Step.Compile {
    const c_lib = b.addLibrary(.{
        .name = name,
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            // libc, because c/blake3.c includes <string.h> and <assert.h>
            // and the hashers call memcpy/memset through it.
            .link_libc = true,
        }),
    });
    const c_mod = c_lib.root_module;

    // For the sources' own quoted includes: every file in c/ includes
    // "blake3_impl.h" or "blake3.h" by bare name.
    c_mod.addIncludePath(b.path("c"));

    for (core_sources) |source| {
        c_mod.addCSourceFile(.{
            .file = b.path(source),
            .flags = &c_flags,
        });
    }

    switch (Simd.for_arch(target.result.cpu.arch, portable)) {
        // Each x86 kernel is compiled by `add_x86_kernel`, on its own and
        // for one instruction set. The core sources above keep the caller's
        // target: raising it for the whole library would let `c/blake3.c`
        // and `c/blake3_dispatch.c` themselves be compiled for an
        // instruction set the dispatcher has not yet confirmed the CPU has.
        .x86_intrinsics => {
            // `std.Target.Query.fromTarget` keeps a pointer to the CPU model
            // it is given, and each kernel module keeps that query for the
            // rest of the build, so the target the queries are derived from
            // has to live that long. One copy in the build's arena serves
            // all four kernels.
            const base = b.allocator.create(std.Target) catch @panic("OOM");
            base.* = target.result;
            for (x86_kernels) |kernel| {
                add_x86_kernel(b, c_mod, base, optimize, name, kernel);
            }
        },
        .neon => {
            c_mod.addCMacro(neon_kernel.macro[0], neon_kernel.macro[1]);
            c_mod.addCSourceFile(.{
                .file = b.path(neon_kernel.source),
                .flags = &c_flags,
            });
        },
        .none => for (no_simd_macros) |macro| {
            c_mod.addCMacro(macro[0], macro[1]);
        },
    }

    // oneTBB stays off, as upstream's default (`c/CMakeLists.txt:20`,
    // `option(BLAKE3_USE_TBB ... OFF)`): `c/blake3_tbb.cpp` is a C++ file
    // that would need a C++20 toolchain, oneTBB and `-fno-exceptions`, and
    // none of it is core. `c/blake3.h:72-75` only declares
    // `blake3_hasher_update_tbb` under `BLAKE3_USE_TBB`, so with the macro
    // undefined the core builds without it and the facade never sees the
    // declaration.

    // Installing the header also puts it on the include path of anything that
    // links this artifact, so a C consumer needs nothing from this tree to
    // call it. blake3.h is the only public header upstream installs
    // (`c/CMakeLists.txt:292`).
    c_lib.installHeader(b.path("c/blake3.h"), "blake3.h");

    return c_lib;
}

/// Compiles the full graph, the tests and the example for one matrix target
/// and attaches all of them to `step`.
///
/// Building the test binary is what makes this a check of the facade rather
/// than of an unreferenced archive: Zig analyses a function body only when
/// something calls it, `tests.zig` calls every public facade method, and so
/// compiling it for a target analyses all of them for that target. The full C
/// source is compiled by the same graph. Nothing is run here, so every
/// result this step produces is compile evidence and not a claim that a
/// cross-built binary executed.
fn add_target_check(
    b: *std.Build,
    step: *std.Build.Step,
    query: std.Target.Query,
    optimize: std.builtin.OptimizeMode,
    portable: bool,
    library: Library,
) void {
    const cross_target = b.resolveTargetQuery(query);
    // The triple names the cross artifacts. Six targets in one build graph
    // otherwise produce six steps called "blake3", which makes `--summary
    // all` useless for telling them apart.
    const triple = cross_target.result.zigTriple(b.allocator) catch @panic("unspellable target");

    const cross = add_graph(b, cross_target, optimize, portable, library, false);

    const cross_test_mod = b.createModule(.{
        .root_source_file = b.path(test_source),
        .target = cross_target,
        .optimize = optimize,
        .link_libc = true,
    });
    cross_test_mod.addImport(lib_name, cross.module);
    step.dependOn(&b.addTest(.{
        .name = b.fmt("blake3-tests-{s}", .{triple}),
        .root_module = cross_test_mod,
    }).step);

    const cross_example_mod = b.createModule(.{
        .root_source_file = b.path(example_source),
        .target = cross_target,
        .optimize = optimize,
        .link_libc = true,
    });
    cross_example_mod.addImport(lib_name, cross.module);
    step.dependOn(&b.addExecutable(.{
        .name = b.fmt("blake3-smoke-{s}", .{triple}),
        .root_module = cross_example_mod,
    }).step);
}

/// Builds `smoke.zig` against `module`, returning the executable. The caller
/// decides whether it is also run: only the host example is.
fn add_example(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    module: *std.Build.Module,
    name: []const u8,
) *std.Build.Step.Compile {
    const example_mod = b.createModule(.{
        .root_source_file = b.path(example_source),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    example_mod.addImport(lib_name, module);
    return b.addExecutable(.{
        .name = name,
        .root_module = example_mod,
    });
}

/// Builds `tests.zig` against `module`, returning the test compile step.
fn add_tests(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    module: *std.Build.Module,
    name: []const u8,
) *std.Build.Step.Compile {
    const test_mod = b.createModule(.{
        .root_source_file = b.path(test_source),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_mod.addImport(lib_name, module);
    return b.addTest(.{ .name = name, .root_module = test_mod });
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const portable = b.option(
        bool,
        "portable",
        "Compile the scalar core only, for any target: no SIMD kernel is " ++
            "linked in and upstream's BLAKE3_NO_* macros are defined. The " ++
            "facade, the tests and the example are unchanged, so the same " ++
            "official vectors can be gated against the dispatched kernels " ++
            "and against blake3_portable.c alone. Ignored in system mode.",
    ) orelse false;

    const system_default = b.option(
        bool,
        "system",
        "Link an installed libblake3 instead of compiling c/, and translate " ++
            "the installed blake3.h instead of the bundled one. This supplies " ++
            "the default of systemIntegrationOption(\"blake3\"); a build " ++
            "runner that decides the mode itself (-fsys=blake3) overrides it.",
    ) orelse false;

    const use_system = b.systemIntegrationOption(lib_name, .{ .default = system_default });
    const library: Library = if (use_system) .system else .bundled;

    const graph = add_graph(b, target, optimize, portable, library, true);

    // In system mode there is no artifact from this tree to install, and
    // installing an empty stand-in would be a claim this build cannot make.
    if (graph.c_lib) |c_lib| b.installArtifact(c_lib);

    // `zig build` installs the library and its header and compiles the
    // example. The example is the cheapest thing that proves the facade, the
    // translated header and the C archive agree on types, symbols and
    // link-time dependencies. It is compiled, not installed: it is a proof,
    // not a deliverable.
    const example = add_example(b, target, optimize, graph.module, "blake3-smoke");
    b.getInstallStep().dependOn(&example.step);

    // A run artifact already depends on building the executable, which
    // depends on compiling the C and linking the facade. `zig build smoke`
    // deliberately does not depend on the install step: installing is
    // `zig build`'s job and conflating the two would make a smoke run depend
    // on the install layout.
    const run_example = b.addRunArtifact(example);
    if (b.args) |args| run_example.addArgs(args);
    b.step("smoke", "Run the deterministic example program").dependOn(&run_example.step);

    // The test root is `tests.zig`, which names the test blocks; a root that
    // only re-exported them would discover no tests and still exit zero.
    const unit_tests = add_tests(b, target, optimize, graph.module, "blake3-tests");
    b.step("test", "Run the behavioural tests").dependOn(&b.addRunArtifact(unit_tests).step);

    // The cross target gate. Compiling the tests and the example for each
    // target is what makes it a check of the facade rather than of an
    // unreferenced archive, and `add_target_check` says why.
    const check_step = b.step(
        "check",
        "Compile the C core, the facade, the tests and the example for the " ++
            "six-target matrix without running any of them",
    );
    if (!target.query.isNative()) {
        add_target_check(b, check_step, target.query, optimize, portable, library);
    } else {
        for (check_targets) |query| {
            add_target_check(b, check_step, query, optimize, portable, library);
        }
    }

    // Which kernels this configuration compiles is a fact worth reading out
    // of the build rather than inferring from a cache directory. This is a
    // configure-time line, not a gate result.
    if (library == .bundled) {
        std.debug.print("blake3: {s}, {s}\n", .{
            Simd.for_arch(target.result.cpu.arch, portable).kind(),
            if (portable) "(-Dportable=true)" else "(default kernels)",
        });
    } else {
        std.debug.print("blake3: system libblake3 (-lblake3), installed blake3.h\n", .{});
    }
}
