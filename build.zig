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
//!   -Dlinkage=static   a static archive, `libblake3.a`. This is the default
//!   -Dlinkage=dynamic    and it is what this package produced before the
//!                        option existed, so a caller who passes nothing
//!                        changes nothing. `dynamic` builds a shared object
//!                        with a real export surface and a position-
//!                        independent closure; see "Static and shared
//!                        delivery" below. In system mode this graph builds
//!                        no artifact at all, so there the option names the
//!                        kind of *installed* library to bind to instead, and
//!                        it defaults to `dynamic`, which is the kind an
//!                        installed `libblake3` normally is.
//!   -Dsystem=true      link an installed `libblake3` instead of compiling
//!                      `c/`, and translate the installed `blake3.h` instead
//!                      of the bundled one, through the same `libblake3.pc`
//!                      the link line asks. See the note on
//!                      `systemIntegrationOption` below.
//!   -Dtarget=<triple>  build for one target; `zig build check` then checks
//!                      that target only instead of the whole matrix.
//!   -Druntime=true     resolve the native entry points at run time instead
//!                      of linking them. The facade keeps the same translated
//!                      header and the same public types; each selected native
//!                      function becomes a dispatch through one
//!                      process-lifetime table an explicit `load(source)`
//!                      fills, and the module links no archive. Independent
//!                      of `-Dlinkage`, which still decides which artifact
//!                      this build delivers and installs, and independent of
//!                      `-Dsystem`, which chooses whose header the
//!                      translation reads; see "System-library mode" below
//!                      for what the pair means together. Default off, and a
//!                      linked build is unchanged in every respect. The
//!                      dispatch itself is `runtime/graph.zig`, which the API
//!                      role owns; `add_graph` names the exact seam.
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
//! the *installed* header. Translating the bundled 1.8.7 header against an
//! older installed library would describe an ABI that may not be the one on
//! disk (`WISDOM.md` W14), and the converse is the same hazard from the other
//! side: an installed `blake3.h` under a prefix the compiler's default include
//! search does not cover would silently go unread while a *different*
//! `blake3.h` on the default path answered instead. So the translation line
//! asks pkg-config for the same `libblake3.pc` the link line asks, and it is
//! the bundled branch that puts this repository's own `c/` on the translation
//! path instead; `add_graph` is where that difference lives.
//!
//! `-Dsystem=true` and `-Druntime=true` are orthogonal, and combining them is
//! a coherent configuration rather than a refused one. `-Druntime` builds no
//! artifact and links nothing into the module; in system mode there is no
//! artifact to build and no library to link, so the two agree on the same
//! empty link line. What the translation does in that configuration is the
//! part that matters: it reads the *installed* `blake3.h`, through the same
//! `libblake3.pc` the link line would ask, and the generated dispatch is built
//! from that translation (`runtime/graph.zig:188-226` runs the generator over
//! this step's own output). So the declarations the table is generated from
//! describe the installed provider, and the caller names the provider its
//! explicit `load(source)` opens. `mpfr/build.zig:177-186` records the same
//! arrangement for the same reason.
//!
//! What this mode is not is a substitute for a source result: the Nix
//! derivation passes `-Doptimize`, `-Dcpu` and `-Dlinkage` and nothing else
//! (`package.nix:93-96`), so it can never deliver a system-library result.
//!
//! Static and shared delivery
//! --------------------------
//! `-Dlinkage` selects which artifact this package produces, and the default
//! is the one this SDK has always produced: `static`, so a caller that passes
//! nothing gets the same `libblake3.a` it got before the option existed.
//! Nothing about the compiled C changes between the two: the same
//! `core_sources`, the same selected kernels, the same language level, the
//! same per-ISA targets. The option selects the *delivery*, never the
//! dispatch.
//!
//! `dynamic` is a real shared object, which takes three things this build
//! would otherwise not do:
//!
//!   * **Position independence on every compilation unit, including the ones
//!     compiled independently.** The library's own module is PIC because a
//!     shared library has to be; the four x86 kernel objects are separate
//!     `b.addObject` compilations with their own targets, and nothing about
//!     `addObject` implies that their result is relocatable. `add_x86_kernel`
//!     therefore takes the linkage and sets `.pic = true` on the kernel
//!     module, so an object built for one instruction set is still linkable
//!     into an image another one can load. Upstream's own recipe is the same
//!     pair of flags with `-fPIC` in front of each kernel
//!     (`c/README.md:320-326`).
//!   * **An export surface.** Upstream's shared build compiles with hidden
//!     default visibility (`c/CMakeLists.txt:153`,
//!     `C_VISIBILITY_PRESET hidden`) and lets `BLAKE3_API`
//!     (`c/blake3.h:7-27`) be the only thing that widens it, so the exported
//!     set is exactly the declarations that macro decorates. This build adds
//!     `-fvisibility=hidden` for the same reason, which needs no version
//!     script and no hand-written export list: `c/blake3.h:20-22` resolves
//!     `BLAKE3_API` to `__attribute__((visibility("default")))` on GCC and
//!     Clang, so the nine public entry points stay exported and every
//!     internal cross-translation-unit symbol stays private. On Windows
//!     `-fvisibility` does nothing, so the export surface comes from the DLL
//!     macros instead; see the next paragraph.
//!   * **The DLL macros, split the way upstream splits them.**
//!     `c/blake3.h:7-19` reads `BLAKE3_DLL` together with
//!     `BLAKE3_DLL_EXPORTS` and becomes `__declspec(dllexport)`,
//!     `__declspec(dllimport)` or undecorated, and `c/CMakeLists.txt:139-145`
//!     sets them `PUBLIC` and `PRIVATE` respectively when
//!     `BUILD_SHARED_LIBS` is on. This build does the same: the library's own
//!     compile line gets both, so the definitions are exported; the
//!     translation gets `BLAKE3_DLL` alone, so the declarations a consumer
//!     sees are imported rather than re-exported; and the installed
//!     `libblake3.pc` carries `-DBLAKE3_DLL` in `Cflags`, which is upstream's
//!     own `PKG_CONFIG_CFLAGS` line for a shared build
//!     (`c/CMakeLists.txt:144`). A static build defines none of the three,
//!     which is why `c/blake3.h:17` leaves `BLAKE3_API` empty there.
//!
//! The soname is upstream's, not a number invented here.
//! `c/CMakeLists.txt:150-155` sets `VERSION ${PROJECT_VERSION}` to 1.8.7 and
//! `SOVERSION` to 0, and `b.addLibrary`'s `version` field is what
//! `std/Build/Step/Compile.zig:488-515` turns into that shape: `libblake3.so.0.1.8`
//! with `libblake3.so.0` and `libblake3.so` beside it on ELF
//! (`Compile.zig:1824-1832`, and `wantSharedLibSymLinks` at
//! `lib/std/Build.zig:2717-2719` says there are none on Windows, where
//! `blake3.dll` and its import library `blake3.lib` are what land instead,
//! `Compile.zig:499-500`), and `libblake3.0.dylib` with `libblake3.dylib`
//! beside it on Darwin (`Compile.zig:492-498`, install name
//! `@rpath/libblake3.0.dylib` at `:1497-1500`). One honest difference:
//! `std.SemanticVersion` has three components and upstream's file name has
//! four, so this build installs `libblake3.so.0.1.8` where CMake would
//! install `libblake3.so.0.1.8.7`. The *soname* — the number a consumer's
//! `DT_NEEDED` records, and the string a `.system` load has to name — is
//! `libblake3.so.0` either way.
//!
//! WASI has no dynamic loader. A shared request fails the corresponding
//! `check` step instead of substituting a static archive. Windows uses its
//! PE/COFF loader and supports shared delivery and explicit runtime loading.
//!
//! Installed closure
//! -----------------
//! `zig build` installs, in bundled mode:
//!
//!   * the native library and `blake3.h`, through `b.installArtifact` and
//!     the `installHeader` call in `add_c_library`; `blake3.h` is the only
//!     public header upstream installs (`c/CMakeLists.txt:292`), and
//!     installing it also puts it on the include path of anything that links
//!     this artifact.
//!   * `lib/pkgconfig/libblake3.pc`, generated by `add_pkg_config` from
//!     upstream's own `c/libblake3.pc.in` field for field. `prefix` is
//!     `${pcfiledir}/../..` rather than CMake's configured absolute prefix, so
//!     the installed file is correct wherever `--prefix` put it.
//!   * `share/licenses/blake3/` with the three licence texts and the three
//!     provenance records, through `install_licence_records`. A private
//!     repository removes no licence obligation, and a package that ships a
//!     binary without them is the failure this prevents.
//!
//! System mode installs none of that: nothing was compiled from this tree, so
//! there is no artifact to describe and no header this build is the source
//! of. `zig build` in that mode installs nothing from this package, and says
//! so on stdout.
//!
//! Published routes
//! -----------------
//! This package publishes the routes below, and one name it deliberately does
//! not publish:
//!
//!   * `dep.module("blake3")`: the Zig facade, `zig/root.zig`. This is the one
//!     registered module. It carries `link_libc`, the translated header as
//!     `c`, and the library behind it, so a dependent that adds this module
//!     needs nothing further to call the facade or to reach `blake3.c`.
//!   * `blake3.c` on that same module: the translated header itself, for a
//!     caller that needs a declaration the facade does not name. It is
//!     deliberately *not* registered as a module of its own: `addModule("c")`
//!     would make `dep.module("c")` resolve, and that route hands over the
//!     same declarations without the library that satisfies them, which is a
//!     reachability a dependent cannot tell from support.
//!   * `dep.artifact("blake3")`: the compiled native library, in bundled
//!     mode only, in whichever `-Dlinkage` selected. This is the C-ABI route
//!     for a dependent that links the library into its own C or Zig build.
//!     System mode installs no artifact from this tree, so that call has
//!     nothing to find there and the dependent links the installed library
//!     instead.
//!   * the installed `blake3.h` and the native library under `zig-out/`,
//!     for a C consumer that includes the header and links the artifact.
//!     `zig build` installs both in bundled mode; system mode installs
//!     neither.
//!   * the installed `lib/pkgconfig/libblake3.pc` and `share/licenses/blake3/`,
//!     which make that C consumer a package rather than a source drop:
//!     `pkg-config --cflags --libs libblake3` answers for the install, and
//!     the licence material travels with the binary it covers.
//!
//! `README.zig.md` states the same routes for a reader deciding what to
//! import, and `zig/root.zig` states the Zig one on the module itself.

const std = @import("std");

/// The runtime-loading build half, owned by the API role.
///
/// `createModule` builds the generated dispatch that replaces
/// `translate.createModule()` under `-Druntime`; it makes the loader-core
/// module itself and re-exports `LoadSource`/`LoadError` from it.
/// `createCoreModule` builds that same core module for the *linked* branch,
/// where there is no dispatch to carry the types and the facade's `rt` import
/// is where they come from (`zig/root.zig:154,174,180`).
///
/// The two branches must not both call `createCoreModule`. `LoadSource` and
/// `LoadError` are this SDK's public types, so they have to be the *same* types
/// in one build: a second core instance would be a second, nominally distinct
/// `LoadSource`, and `blake3.load(source)` would be handing the facade's type
/// to a function expecting the dispatch's. `add_graph` documents the branch
/// and is the only function that calls either of these.
const graph = @import("runtime/graph.zig");

/// `build.zig.zon` itself. `@import` of the manifest is how a build script
/// reads `.version` without a second copy of it; `spglib/build.zig:4` uses
/// the same import.
const manifest = @import("build.zig.zon");

/// `build.zig.zon .version`, parsed. The parse is the loud part: a manifest
/// whose `.version` is not a semantic version fails to configure here rather
/// than being silently compared as something else.
const manifest_version = std.SemanticVersion.parse(manifest.version) catch
    @panic("build.zig.zon: .version is not a semantic version");

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

/// Upstream's own version, read out of `c/blake3.h:33`
/// (`#define BLAKE3_VERSION_STRING "1.8.7"`) and out of `c/CMakeLists.txt:13`
/// (`project(libblake3 VERSION 1.8.7 ...)`). It is the version of the C
/// library, and `build.zig.zon .version` carries the same string; `build`
/// refuses to configure when the two drift apart, so the pkg-config `Version:`
/// field, the shared object's file name and the package manifest cannot
/// describe three different releases.
const upstream_version: std.SemanticVersion = .{ .major = 1, .minor = 8, .patch = 7 };

/// The soname `libblake3.so.0` — the shared library's ABI number, upstream's
/// `SOVERSION 0` (`c/CMakeLists.txt:150-155`).
const abi_version: std.SemanticVersion = .{ .major = 0, .minor = 1, .patch = 8 };

/// The carried licence and provenance material `zig build` installs under
/// `share/licenses/blake3/`.
///
/// All three upstream texts ship because upstream offers three grants for one
/// body of work and states the choice in `README.upstream.md:191-197`: "This
/// work is released into the public domain with CC0 1.0. Alternatively, it is
/// licensed under any of the following: Apache 2.0, Apache 2.0 with LLVM
/// exceptions". A consumer takes whichever it wants, so the package carries
/// all three and `NOTICE.md` says which is which. The other three are this
/// fork's own records, and a private repository removes no obligation. The
/// order is the one `NOTICE.md` uses: upstream's texts first, then the
/// records that describe what this fork did to them.
const licence_records = [_][]const u8{
    "LICENSE_A2",
    "LICENSE_A2LLVM",
    "LICENSE_CC0",
    "NOTICE.md",
    "FORK-LICENSE.md",
    "UPSTREAM.md",
};

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

/// The C flags a shared build adds on top of `c_flags`.
///
/// `-fvisibility=hidden` is upstream's own choice for the library:
/// `c/CMakeLists.txt:153` sets `C_VISIBILITY_PRESET hidden` on the target, and
/// `c/blake3.h:20-22` widens exactly one macro, `BLAKE3_API`, to
/// `__attribute__((visibility("default")))` under GCC and Clang. With the
/// default hidden, the exported set is precisely the public entry points
/// `c/blake3.h:63-80` decorates, and the internal cross-translation-unit
/// symbols the four kernels and `c/blake3_dispatch.c` share
/// (`blake3_compress_in_place_sse41` and the rest, declared at
/// `c/blake3_impl.h:258-308`) stay private to the image. No version script
/// and no hand-written export list is involved: the header already says which
/// symbols are public, and a second list beside it could only drift from it.
///
/// On Windows this flag has no effect, and the export surface comes from the
/// DLL macros `add_c_library` sets instead.
///
/// It reaches the *shared* delivery only, which is a deliberate deviation
/// from upstream: `c/CMakeLists.txt:150-155` sets `C_VISIBILITY_PRESET
/// hidden` on the target unconditionally, so upstream's own static archive is
/// built with it too. Two reasons this build does not follow it there:
///
///   * `static` is the delivery every gate in this repository's recorded
///     history observed. Adding a flag to that command line would change a
///     verified build for no observable gain, and visibility is inert for it:
///     a hidden symbol in an archive is still linkable, because visibility
///     governs a dynamic symbol table and an archive has none.
///   * The flag only does work where there is a dynamic symbol table to
///     narrow, which is exactly the shared object. In the static archive the
///     exported set is not a concept.
///
/// So the deviation is confined to an inert property of the static artifact,
/// and the shared artifact — the one that has an export surface — matches
/// upstream exactly.
const c_flags_shared = [_][]const u8{"-fvisibility=hidden"};

/// The flags one C translation unit of this library is compiled with.
///
/// Every source in `core_sources`, every selected kernel and the NEON source
/// goes through this one function, so a flag cannot reach the core and miss
/// a kernel or the reverse. That matters for `-fvisibility=hidden` in
/// particular: a kernel object compiled with the default visibility would
/// export `blake3_compress_in_place_sse41` from a shared object even though
/// upstream never exports it.
fn cUnitFlags(linkage: std.builtin.LinkMode) []const []const u8 {
    return if (linkage == .dynamic) &c_flags_shared_flags else &c_flags;
}

/// `c_flags` and `c_flags_shared` concatenated for the shared build.
///
/// `++` is array concatenation, and both operands are comptime constants, so
/// this is a compile-time value rather than a buffer built at configure
/// time. It exists so the language level is written once: a shared build that
/// quietly compiled `c/blake3.c` at a different C standard than its kernels
/// would be a much harder defect to see than a duplicated literal.
const c_flags_shared_flags = c_flags ++ c_flags_shared;

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
    /// The facade module, with `c` bound to the translated header for the
    /// library this graph compiled or selected.
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
/// rest. The translated header is imported rather than registered in both
/// forms; the published routes are named above.
fn add_graph(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    portable: bool,
    library: Library,
    linkage: std.builtin.LinkMode,
    runtime_loaded: bool,
    public: bool,
) Graph {
    const c_lib: ?*std.Build.Step.Compile = if (library == .bundled)
        add_c_library(b, target, optimize, portable, linkage, artifact_name(b, target, public))
    else
        null;

    const translate = b.addTranslateC(.{
        .root_source_file = b.path(translate_header),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    if (library == .bundled) {
        // The linkage this target can actually carry, resolved once here so
        // the translation and the library cannot disagree about it, and
        // resolved in this branch only because this branch is the only one in
        // which this build delivers anything. `add_c_library` resolves the
        // same value for the same reason. In system mode there is no artifact
        // to deliver, so a platform fact about *this* build's own shared
        // object says nothing about which kind of installed library is on the
        // machine, and `-Dlinkage` keeps its other meaning there: a
        // preference passed to `linkSystemLibrary`.
        const delivered = deliveredLinkage(target, linkage);

        // `zig/translate.h` includes `<blake3.h>`, and this is the only
        // header search path the translation has. Without it the translation
        // would silently bind to whatever `blake3.h` happens to be installed
        // on the build machine, describing that library's declarations
        // rather than the ones this build compiles (`WISDOM.md` W14).
        translate.addIncludePath(b.path("c"));
        if (delivered == .dynamic) {
            // The declaration half of upstream's DLL split. The library's own
            // compile line gets `BLAKE3_DLL` and `BLAKE3_DLL_EXPORTS`
            // (`add_c_library`); this line gets `BLAKE3_DLL` alone, so
            // `c/blake3.h:12-13` decorates the nine declarations with
            // `__declspec(dllimport)` on a Windows consumer rather than
            // re-exporting them from a module that does not define them.
            // This is upstream's own `PUBLIC` half
            // (`c/CMakeLists.txt:140-141`); without it the translation and
            // the archive would describe two different linkages.
            translate.defineCMacro("BLAKE3_DLL", "1");
        }
    } else {
        // System mode, and the half of `WISDOM.md` W14 that is easy to get
        // wrong in the *other* direction. The bundled branch above names the
        // header this build compiles. This branch must name the header of the
        // installed library that is actually linked, and the only authority on
        // where an installed `blake3.h` lives is the same `libblake3.pc` the
        // link below asks about: a distribution that installs the header
        // outside the compiler's default include search (a `/usr/local`
        // prefix, a Nix store path, a `-I` the `.pc` carries) would otherwise
        // have its translation bound to a *different* `blake3.h` that happens
        // to be on the default path, so the declarations and the library would
        // describe two providers and the mismatch is silent
        // (`lmdb/build.zig:694-703` and `sheenbidi/build.zig:545-578` close the
        // same gap on the same line of their own graphs).
        //
        // The same options the module link below passes, so the include path
        // and the `-lblake3` come from one pkg-config answer and not from two.
        // This is deliberately *not* guarded by `runtime_loaded`: under
        // `-Druntime` the header still has to be the installed one, because
        // the dispatch is generated from this same translation. It is also not
        // a fallback link. `TranslateC.setUpModule` is what copies a system
        // library from this step onto a module
        // (`lib/std/Build/Step/TranslateC.zig:89-100`), and the runtime branch
        // below never calls it: its `c` import is the generated dispatch
        // (`runtime/graph.zig:120-136`), which is built from this step's
        // output and reaches no library at all. Under `-Druntime` the module
        // therefore links nothing, here or below, which is what the runtime
        // route is.
        translate.linkSystemLibrary(lib_name, .{
            .use_pkg_config = .force,
            .preferred_link_mode = linkage,
        });
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
    // Where the runtime-loading seam is
    // ---------------------------------
    // `runtime/graph.zig`, which the API role owns, exposes
    //
    //     pub fn createModule(
    //         b: *std.Build,
    //         translate: *std.Build.Step.TranslateC,
    //         target: std.Build.ResolvedTarget,
    //         optimize: std.builtin.OptimizeMode,
    //     ) *std.Build.Module
    //
    // and `-Druntime` substitutes that one call for `translate.createModule()`.
    // It takes the `TranslateC` step this function has already built, so the
    // generated dispatch keeps the exact translated type and constant
    // namespace rather than compiling a second copy of the native extern
    // structs and casting between two nominally distinct Zig modules: every
    // type and constant in the dispatch is re-exported from the translation it
    // was generated from, so `c.blake3_hasher` in the facade and the
    // declaration behind the table are one type.
    //
    // `-Dlinkage` is orthogonal and keeps meaning what it means: it selects
    // which artifact this build *delivers* and installs, never which one the
    // module dispatches through.
    //
    // The `rt` import is for the linked branch only, and the reason is the
    // nominal type rather than the code. `graph.createModule` creates the one
    // core-module instance the generated dispatch uses and re-exports
    // `LoadSource`/`LoadError` from it; a second instance created here for the
    // facade would be a *different* `LoadSource`, and `blake3.load(source)`
    // would be handing the facade's type to a function expecting the
    // dispatch's. One instance per build, no more. In a linked build there is
    // no dispatch, so the facade's own `rt` import is where those two public
    // types come from; `zig/root.zig` picks between the two with a comptime
    // branch on `runtime_loaded`, so the module a configuration does not need
    // is never resolved and never compiled.
    if (runtime_loaded) {
        // A loaded provider must arrive through the platform loader, so the
        // link line names nothing. Linking the archive as well would make the
        // linker resolve the same symbols statically and the runtime route
        // would quietly be a linked one. The artifact itself is still built
        // and installed above, because delivery and dispatch are separate
        // questions: the whole point of the mode is that a caller may name a
        // provider this tree did not build.
        module.addImport("c", graph.createModule(b, translate, target, optimize));
    } else {
        // The translated header is imported, never registered. `addModule("c")`
        // would make `dep.module("c")` resolve and hand a dependent the same
        // declarations without the library that satisfies them; `blake3.c` on
        // the facade is the supported way in and carries the facade's own
        // linkage.
        module.addImport("c", translate.createModule());
        module.addImport("rt", graph.createCoreModule(b, target, optimize));
        if (c_lib) |lib| {
            module.linkLibrary(lib);
        } else {
            // System mode, linked. `.force` asks `libblake3.pc` for its cflags
            // and makes pkg-config mandatory, so an installed tree whose own
            // metadata cannot answer stops the build instead of degrading to a
            // bare `-lblake3` the declarations above never described.
            //
            // `linkage` names the kind of *installed* library to bind to here,
            // not an artifact this graph builds: there is none in this mode.
            // `preferred_link_mode` is what `linkSystemLibrary` already
            // defaults to (`lib/std/Build/Module.zig:359`), so a caller who
            // passes nothing gets the behaviour this package has always had,
            // and `-Dlinkage=static` is the one thing that changes it — to
            // bind `libblake3.a`, which is what the option's name says here.
            //
            // The same options the translation line above passes, spelled out
            // rather than left to the default, so the include path the
            // declarations came from and the `-lblake3` they bind to are one
            // pkg-config answer rather than two that can disagree.
            module.linkSystemLibrary(lib_name, .{
                .use_pkg_config = .force,
                .preferred_link_mode = linkage,
            });
        }
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
/// `optimize` and the object format are the caller's. `pic` follows
/// `linkage`: it stays unset for a static archive, which is the mode this
/// package has always produced and which needs no relocatability, and it is
/// set for a shared object, where the omission would be a link failure rather
/// than a lost optimisation. Upstream's own shared recipe compiles each
/// kernel with `-fPIC` before its `-m` flag (`c/README.md:320-326`), so this
/// is the same requirement upstream states rather than one invented here.
/// `Module.pic` reaches the command line as `-fPIC`/`-fno-PIC` through
/// `lib/std/Build/Module.zig:554`.
///
/// `name` is the library's artifact name, so the object is named after it and
/// one matrix target does not produce sixteen steps called the same thing.
fn add_x86_kernel(
    b: *std.Build,
    c_mod: *std.Build.Module,
    base: *const std.Target,
    optimize: std.builtin.OptimizeMode,
    linkage: std.builtin.LinkMode,
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
        .pic = if (linkage == .dynamic) true else null,
    });
    // For the kernel's own quoted include of "blake3_impl.h", the same
    // include path `add_c_library` gives the core sources. The flags are the
    // shared C flags for the same reason: a kernel is one of this library's
    // translation units and compiles under the same configuration macros, so
    // it sees the same visibility the core does.
    kernel_mod.addIncludePath(b.path("c"));
    kernel_mod.addCSourceFile(.{
        .file = b.path(kernel.source),
        .flags = cUnitFlags(linkage),
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
/// `requested` is the linkage the caller asked for. What it selects is the
/// artifact and nothing else about the compilation: the same sources, the
/// same macros, the same kernel selection, the same per-ISA targets. What a
/// shared artifact adds is its own requirements — the soname, PIC on every
/// module including the kernel objects, the export surface, and the two DLL
/// macros upstream splits between the definitions and the declarations.
///
/// `deliveredLinkage` decides what this target can actually carry, and it
/// refuses rather than substituting: a target whose OS has no dynamic linker
/// cannot take the shared artifact this function would otherwise build, and a
/// static archive handed back in its place is not the artifact that was asked
/// for. `-Dlinkage=static` is the caller's way to say so. `zig build check`
/// walks a WASI target and reports that refusal through its own failing step
/// (`add_target_check`), so the boundary is reachable from the published
/// six-target matrix and surfaces as a configure-time message rather than a
/// link error.
///
/// `name` is the artifact name this graph installs or reports; see
/// `artifact_name`.
fn add_c_library(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    portable: bool,
    requested: std.builtin.LinkMode,
    name: []const u8,
) *std.Build.Step.Compile {
    const linkage = deliveredLinkage(target, requested);
    const c_lib = b.addLibrary(.{
        .name = name,
        .linkage = linkage,
        // Upstream's `SOVERSION 0` with `VERSION 1.8.7`
        // (`c/CMakeLists.txt:150-155`). `version` is null for a static
        // archive, which has no soname and no versioned file name.
        .version = if (linkage == .dynamic) abi_version else null,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            // libc, because c/blake3.c includes <string.h> and <assert.h>
            // and the hashers call memcpy/memset through it.
            .link_libc = true,
            // A shared library is position-independent whether or not this
            // says so; naming it makes the requirement explicit on the same
            // module that carries the kernel objects.
            .pic = if (linkage == .dynamic) true else null,
        }),
    });
    const c_mod = c_lib.root_module;
    const flags = cUnitFlags(linkage);

    // For the sources' own quoted includes: every file in c/ includes
    // "blake3_impl.h" or "blake3.h" by bare name.
    c_mod.addIncludePath(b.path("c"));

    // The two DLL macros, on the line that compiles the *definitions*, split
    // exactly as `c/CMakeLists.txt:139-145` splits them: `BLAKE3_DLL` marks
    // the declarations as belonging to a shared library, and
    // `BLAKE3_DLL_EXPORTS` says this compilation is the one producing it.
    // `c/blake3.h:9-14` reads the pair to choose `__declspec(dllexport)`
    // over `__declspec(dllimport)`. They matter only on Windows and Cygwin
    // (`c/blake3.h:8`); everywhere else `BLAKE3_API` is the visibility
    // attribute and these two are unread, so defining them on ELF or macOS
    // is upstream's own behaviour rather than a portability exception.
    if (linkage == .dynamic) {
        c_mod.addCMacro("BLAKE3_DLL", "1");
        c_mod.addCMacro("BLAKE3_DLL_EXPORTS", "1");
    }

    for (core_sources) |source| {
        c_mod.addCSourceFile(.{
            .file = b.path(source),
            .flags = flags,
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
                add_x86_kernel(b, c_mod, base, optimize, linkage, name, kernel);
            }
        },
        .neon => {
            c_mod.addCMacro(neon_kernel.macro[0], neon_kernel.macro[1]);
            c_mod.addCSourceFile(.{
                .file = b.path(neon_kernel.source),
                .flags = flags,
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
    linkage: std.builtin.LinkMode,
    runtime_loaded: bool,
) void {
    const cross_target = b.resolveTargetQuery(query);
    // The triple names the cross artifacts. Six targets in one build graph
    // otherwise produce six steps called "blake3", which makes `--summary
    // all` useless for telling them apart.
    const triple = cross_target.result.zigTriple(b.allocator) catch @panic("unspellable target");
    // Only in bundled mode. This graph produces an artifact only there, so
    // "can this target carry a shared one" has an answer only there; in system
    // mode `linkage` names the kind of *installed* library the facade binds to
    // and no artifact of ours is delivered, so refusing a shared delivery this
    // build never attempted would report a boundary it does not have.
    if (library == .bundled and linkage == .dynamic and !targetHasDynamicLinker(cross_target)) {
        step.dependOn(&b.addFail(b.fmt(
            "blake3: shared delivery is unsupported for {s}; no static substitution. Use -Dlinkage=static.",
            .{triple},
        )).step);
        return;
    }

    const cross = add_graph(b, cross_target, optimize, portable, library, linkage, runtime_loaded, false);

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

/// Writes `lib/pkgconfig/libblake3.pc` and installs it.
///
/// Every field is upstream's, from `c/libblake3.pc.in`, so a consumer that
/// already asks pkg-config about a BLAKE3 built by CMake gets the same answer
/// here. Two things differ from upstream's *configured* file, both
/// deliberately:
///
///   * `prefix` is `${pcfiledir}/../..` instead of CMake's substituted
///     `@CMAKE_INSTALL_PREFIX@`. This graph does not know where `--prefix`
///     will point when it writes the file, and CMake does know its own prefix
///     at configure time because CMake *is* the build system. pkg-config
///     resolves `${pcfiledir}` against the `.pc` file it found, so the
///     installed file is correct wherever the prefix landed, including a Nix
///     store path that is only known at build time.
///   * `Version:` is formatted from `upstream_version`, which `build` has
///     already checked against `build.zig.zon .version`. CMake substitutes
///     `@PROJECT_VERSION@` from `c/CMakeLists.txt:13`; here the same string
///     comes from one constant that refuses to configure when the manifest
///     drifts, so the manifest, this file and the shared object's file name
///     cannot name three different releases.
///
/// `Libs:` is upstream's literal line (`c/libblake3.pc.in:11`) in both
/// variants, because the library *name* does not change with linkage: a C
/// consumer asks for `-lblake3` and the linker resolves it to `libblake3.a`
/// or, through the `libblake3.so` symlink, to the shared object.
///
/// `Cflags:` differs, and only for the shared build: `-DBLAKE3_DLL` is
/// upstream's own `PKG_CONFIG_CFLAGS` entry under `BUILD_SHARED_LIBS`
/// (`c/CMakeLists.txt:139-145`), and it is what makes a consumer's
/// declarations `__declspec(dllimport)` on Windows.
///
/// There is deliberately no `Libs.private`: upstream's template has no such
/// field, and BLAKE3 depends on nothing but libc, which every consumer already
/// links. There is also no `blake3-config.cmake`: upstream's is a CMake
/// target export (`c/CMakeLists.txt:298-318`), not link metadata, and
/// hand-writing a substitute would be a second packaging dialect upstream
/// does not ship.
fn add_pkg_config(b: *std.Build, linkage: std.builtin.LinkMode) void {
    const files = b.addWriteFiles();
    const install = b.addInstallFileWithDir(
        files.add("libblake3.pc", b.fmt(
            \\# Generated by build.zig from upstream's c/libblake3.pc.in.
            \\# Field names and order are upstream's; build.zig's
            \\# add_pkg_config says which two values differ from a
            \\# CMake-configured file and why.
            \\prefix=${{pcfiledir}}/../..
            \\exec_prefix=${{prefix}}
            \\libdir=${{prefix}}/lib
            \\includedir=${{prefix}}/include
            \\
            \\Name: libblake3
            \\Description: BLAKE3 C implementation
            \\Version: {f}
            \\
            \\Requires:
            \\Libs: -L"${{libdir}}" -lblake3
            \\Cflags: -I"${{includedir}}"{s}
            \\
        , .{
            upstream_version,
            // Upstream's PKG_CONFIG_CFLAGS under BUILD_SHARED_LIBS
            // (c/CMakeLists.txt:144); empty for a static build.
            if (linkage == .dynamic) " -DBLAKE3_DLL" else "",
        })),
        .lib,
        "pkgconfig/libblake3.pc",
    );
    b.getInstallStep().dependOn(&install.step);
}

/// Installs the carried licence texts and provenance records under
/// `share/licenses/blake3/`.
///
/// A private repository removes no upstream obligation. Upstream offers three
/// grants for one body of work and states the choice in
/// `README.upstream.md:191-197`, so all three texts ship and `NOTICE.md` says
/// which is which; `FORK-LICENSE.md` records the owner-authorised grant for
/// this fork's own files; `UPSTREAM.md` records the pin and what changed.
/// `libunibreak`'s `build.zig:588-590` and `erfa`'s `build.zig:814-815`
/// install the same way, so this is the workspace's convention rather than one
/// invented here.
///
/// `share/licenses/<name>` is the location both this build and `package.nix`
/// use, which is what lets the packaging layer's own `install -Dm644` be an
/// idempotent overwrite of these bytes rather than a second copy.
fn install_licence_records(b: *std.Build) void {
    for (licence_records) |record| {
        const install = b.addInstallFileWithDir(
            b.path(record),
            .prefix,
            b.fmt("share/licenses/{s}/{s}", .{ lib_name, record }),
        );
        b.getInstallStep().dependOn(&install.step);
    }
}

/// Wires the `after-load` control run of `runtime/misuse.zig`.
///
/// This is the one of that program's three modes a build script can gate: it
/// must *succeed*, so `expectExitCode(0)` is the whole assertion and no value
/// has to be guessed. It is also the control that makes the other two
/// meaningful — the same call through the same table succeeds as soon as a
/// provider is loaded, so a stop in `pre-load` cannot be confused with a build
/// that is broken for some other reason.
///
/// The two failing modes, `pre-load` and `linked-load`, are compiled in every
/// configuration and every optimize mode, and they are *run* by the driver
/// rather than by this graph. That is not an omission: they assert that the
/// process stops, and `Step.Run` in this release exposes only
/// `expectExitCode(u8)` (`Run.zig:628-631`) — there is no
/// "must not exit zero" check — so gating them here would mean writing down an
/// exit code this build has never observed. The driver runs them and records
/// what they printed; the message has to name the library, the function and
/// the way out, which is what makes it that program's job and not a test's.
fn addMisuseRuns(b: *std.Build, misuse: *std.Build.Step.Compile, provider: std.Build.LazyPath) void {
    const step = b.step(
        "runtime-misuse",
        "Run runtime/misuse.zig after-load <provider>: the control that must " ++
            "succeed. The pre-load and linked-load modes must stop and are run " ++
            "and observed by the driver, not asserted here.",
    );
    const run = b.addRunArtifact(misuse);
    run.addArgs(&.{"after-load"});
    // An argument, not an environment variable: `Step.Run` takes a
    // `LazyPath` here (`Run.zig:346-353`), where an environment entry takes
    // only a literal string.
    run.addPrefixedFileArg("", provider);
    run.expectExitCode(0);
    step.dependOn(&run.step);
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

    const linkage_option = b.option(
        std.builtin.LinkMode,
        "linkage",
        "Deliver the native library as a static archive (the default, and " ++
            "what this package has always produced) or as a real shared " ++
            "object with upstream's soname. This selects the delivery and " ++
            "never the dispatch: the same C is compiled either way. In " ++
            "system mode this graph builds no artifact at all, so there the " ++
            "option names the kind of installed library to bind to instead, " ++
            "and it defaults to dynamic.",
    );

    // Two defaults, because the two modes had two. The bundled graph
    // compiled a static archive before this option existed and must keep
    // doing so; `linkSystemLibrary`'s own default is `.dynamic`
    // (`lib/std/Build/Module.zig:359`), and system mode must keep that too.
    // Deriving one from the other would silently change a consumer's linkage
    // in the mode that option was not written for.
    const linkage: std.builtin.LinkMode = linkage_option orelse
        (if (library == .system) .dynamic else .static);

    // `-Druntime` selects the *dispatch*, and it is orthogonal to
    // `-Dlinkage`: the option says which artifact this build delivers and
    // installs, this one says whether the facade calls it through a link line
    // or through a table an explicit `load` fills. Under `-Druntime` nothing
    // is linked into the module at all, so a caller may name a provider this
    // tree did not build -- and the artifact is still built and installed, so
    // a caller may equally name the one it did.
    const runtime_loaded = b.option(
        bool,
        "runtime",
        "Resolve the native entry points at run time instead of linking them. " ++
            "The facade keeps the same translated header and the same public " ++
            "types; each selected native function becomes a dispatch through " ++
            "one process-lifetime table that an explicit load(source) fills, " ++
            "and the module links no archive. Independent of -Dlinkage, which " ++
            "still decides which artifact this build delivers and installs. " ++
            "Default off, and a linked build is unchanged in every respect.",
    ) orelse false;

    // `build.zig.zon .version` and the version this build stamps into
    // `libblake3.pc`, names into the shared object's file name and documents
    // in three other places are one fact. `std.SemanticVersion.parse` fails
    // loudly rather than wrapping a non-version, and the comparison catches a
    // manifest edited without the source it describes — the failure mode
    // `spglib/build.zig:104-106` already guards against in this workspace.
    if (manifest_version.order(upstream_version) != .eq) {
        @panic("build.zig.zon .version no longer matches the version read out " ++
            "of c/blake3.h and c/CMakeLists.txt; see UPSTREAM.md");
    }

    const published = add_graph(b, target, optimize, portable, library, linkage, runtime_loaded, true);

    // In system mode there is no artifact from this tree to install, and
    // installing an empty stand-in would be a claim this build cannot make.
    if (published.c_lib) |c_lib| b.installArtifact(c_lib);

    // The rest of the delivery, not just the archive. A shared object with no
    // pkg-config metadata and a package with no licence material beside the
    // binary are both source drops, not packages: one leaves a C consumer no
    // `-lblake3` to resolve and the other removes an obligation a private
    // repository does not remove. Both are installed only in bundled mode,
    // because in system mode there is no artifact here to describe.
    if (library == .bundled) {
        add_pkg_config(b, linkage);
        install_licence_records(b);
    }

    // `zig build` installs the library and its header and compiles the
    // example. The example is the cheapest thing that proves the facade, the
    // translated header and the C archive agree on types, symbols and
    // link-time dependencies. It is compiled, not installed: it is a proof,
    // not a deliverable.
    const example = add_example(b, target, optimize, published.module, "blake3-smoke");
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
    const unit_tests = add_tests(b, target, optimize, published.module, "blake3-tests");
    b.step("test", "Run the behavioural tests").dependOn(&b.addRunArtifact(unit_tests).step);

    // The runtime gates, and what each one can and cannot prove from a build
    // script.
    //
    // `runtime/load_tests.zig` is a separate test root because the loader's
    // contract is mostly about what happens *between* calls -- a failure that
    // publishes nothing, a retry that is the caller's to make, threads arriving
    // at one attempt -- and none of that is observable from a single call in
    // `tests.zig`. It is runtime-only: its own comptime guard refuses to
    // compile against a linked module, so wiring it unconditionally would be
    // wiring a compile error.
    //
    // Runtime/static uses the caller's separately built shared provider.
    // Neither the SDK nor its tests build an extra provider implicitly.

    const misuse = b.addExecutable(.{
        .name = "blake3-misuse",
        .root_module = b.createModule(.{
            .root_source_file = b.path("runtime/misuse.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{.{ .name = lib_name, .module = published.module }},
        }),
    });

    // `runtime/misuse.zig` is compiled in *both* configurations, because its
    // `linked-load` mode asserts the message a linked build produces and a
    // runtime-only build cannot check that half.
    if (runtime_loaded) {
        if (b.graph.environ_map.get("BLAKE3_TEST_PROVIDER")) |provider_path| {
            addMisuseRuns(b, misuse, .{ .cwd_relative = provider_path });
        } else {
            const misuse_step = b.step("runtime-misuse", "Run the loaded-provider control");
            misuse_step.dependOn(&b.addFail("runtime-misuse requires an explicit BLAKE3_TEST_PROVIDER").step);
        }
        const load_tests = b.addTest(.{
            .name = "blake3-load-tests",
            .root_module = b.createModule(.{
                .root_source_file = b.path("runtime/load_tests.zig"),
                .target = target,
                .optimize = optimize,
                .link_libc = true,
                .imports = &.{.{ .name = lib_name, .module = published.module }},
            }),
        });
        const runtime_fixtures = b.addOptions();
        runtime_fixtures.addOption([]const u8, "vectors_json", @embedFile("test_vectors/test_vectors.json"));
        load_tests.root_module.addOptions("runtime_fixtures", runtime_fixtures);
        // Both provider paths are supplied explicitly by the caller.
        const run_tests = b.addRunArtifact(load_tests);
        run_tests.setCwd(.{ .cwd_relative = b.cache_root.path orelse "." });
        const runtime_step = b.step("runtime-test", "Run loader lifecycle tests; requires explicit BLAKE3_TEST_PROVIDER and BLAKE3_TEST_ALIEN");
        runtime_step.dependOn(&run_tests.step);

        const dispatch = published.module.import_table.get("c").?;
        const core_tests = b.addTest(.{
            .name = "blake3-runtime-core-tests",
            .root_module = b.createModule(.{
                .root_source_file = b.path("runtime/core_tests.zig"),
                .target = target,
                .optimize = optimize,
                .link_libc = true,
                .imports = &.{
                    .{ .name = "dispatch", .module = dispatch },
                    .{ .name = "rt", .module = dispatch.import_table.get("rt").? },
                    .{ .name = "library", .module = dispatch.import_table.get("library").? },
                },
            }),
        });
        const run_core_tests = b.addRunArtifact(core_tests);
        run_core_tests.setCwd(.{ .cwd_relative = b.cache_root.path orelse "." });
        runtime_step.dependOn(&run_core_tests.step);
    }
    b.getInstallStep().dependOn(&misuse.step);

    // The cross target gate. Compiling the tests and the example for each
    // target is what makes it a check of the facade rather than of an
    // unreferenced archive, and `add_target_check` says why.
    const check_step = b.step(
        "check",
        "Compile the C core, the facade, the tests and the example for the " ++
            "six-target matrix without running any of them",
    );
    if (!target.query.isNative()) {
        add_target_check(b, check_step, target.query, optimize, portable, library, linkage, runtime_loaded);
    } else {
        for (check_targets) |query| {
            add_target_check(b, check_step, query, optimize, portable, library, linkage, runtime_loaded);
        }
    }

    // Which kernels this configuration compiles, and which artifact it hands
    // back, are facts worth reading out of the build rather than inferring
    // from a cache directory. These are configure-time lines, not gate
    // results: nothing has been compiled when they print.
    if (library == .bundled) {
        std.debug.print("blake3: {s}, {s}, {s}\n", .{
            Simd.for_arch(target.result.cpu.arch, portable).kind(),
            if (portable) "(-Dportable=true)" else "(default kernels)",
            switch (linkage) {
                .static => "static archive (default)",
                .dynamic => b.fmt("shared object, soname libblake3.so.{d}", .{abi_version.major}),
            },
        });
        if (runtime_loaded) {
            // Dispatch is a separate fact from delivery, and a runtime-loaded
            // build links nothing into the module: the caller names a
            // provider with an explicit `load(source)` and the symbols arrive
            // through the platform loader. Printing it here is what keeps "the
            // library is still built and installed" from reading as "the
            // module links it".
            std.debug.print(
                "blake3: runtime-loaded dispatch (-Druntime=true); no library " ++
                    "is linked into the module, and a provider is named by an " ++
                    "explicit load(source)\n",
                .{},
            );
        }
    } else {
        std.debug.print("blake3: system libblake3 (-lblake3), installed blake3.h, {s}\n", .{
            @tagName(linkage),
        });
    }
}

/// Whether this target's OS has a dynamic linker at all, and therefore
/// whether it can carry a shared object.
///
/// Windows uses its PE/COFF loader without an interpreter path.
/// Other shared targets need a dynamic linker. WASI has neither.
fn targetHasDynamicLinker(target: std.Build.ResolvedTarget) bool {
    return target.result.os.tag == .windows or std.Target.DynamicLinker.kind(target.result.os.tag) != .none;
}

/// Deliver the requested linkage or refuse it before compilation.
/// A static archive is never a substitute for a requested shared library.
fn deliveredLinkage(
    target: std.Build.ResolvedTarget,
    requested: std.builtin.LinkMode,
) std.builtin.LinkMode {
    if (requested == .dynamic and !targetHasDynamicLinker(target)) {
        std.debug.panic(
            "blake3: shared delivery is unsupported for {s}; no static substitution. Use -Dlinkage=static.",
            .{@tagName(target.result.os.tag)},
        );
    }
    return requested;
}
