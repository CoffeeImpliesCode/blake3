const std = @import("std");

/// Runtime dispatch and the facade share one core module so their loader types match.
/// The linked branch builds the core module without a dispatch.
const graph = @import("runtime/graph.zig");

const manifest = @import("build.zig.zon");
const manifest_version = std.SemanticVersion.parse(manifest.version) catch
    @panic("build.zig.zon: .version is not a semantic version");

const lib_name = "blake3";
const facade_source = "zig/root.zig";

const translate_header = "zig/translate.h";

const test_source = "tests.zig";

const example_source = "smoke.zig";

/// Upstream library version (c/blake3.h:33, c/CMakeLists.txt:13).
const upstream_version: std.SemanticVersion = .{ .major = 1, .minor = 8, .patch = 7 };

/// Upstream shared-library ABI version (c/CMakeLists.txt:150-155).
const abi_version: std.SemanticVersion = .{ .major = 0, .minor = 1, .patch = 8 };

const licence_records = [_][]const u8{
    "LICENSE_A2",
    "LICENSE_A2LLVM",
    "LICENSE_CC0",
    "NOTICE.md",
    "FORK-LICENSE.md",
    "UPSTREAM.md",
};

/// Use C11 atomics selected by upstream when stdatomic.h is available (c/blake3_dispatch.c:21-34).
const c_flags = [_][]const u8{"-std=gnu11"};

/// Hide internal symbols in shared builds; BLAKE3_API defines the export surface.
/// Upstream uses hidden visibility for the library (c/CMakeLists.txt:153).
const c_flags_shared = [_][]const u8{"-fvisibility=hidden"};

/// Apply the same C flags to every library translation unit.
fn cUnitFlags(linkage: std.builtin.LinkMode) []const []const u8 {
    return if (linkage == .dynamic) &c_flags_shared_flags else &c_flags;
}

const c_flags_shared_flags = c_flags ++ c_flags_shared;

/// Upstream core library sources (c/CMakeLists.txt:130-134).
const core_sources = [_][]const u8{
    "c/blake3.c",
    "c/blake3_dispatch.c",
    "c/blake3_portable.c",
};

// Build only the library sources, not upstream tests or examples.
/// Upstream's "none" configuration: portable core without SIMD kernels.
const no_simd_macros = [_][2][]const u8{
    .{ "BLAKE3_USE_NEON", "0" },
    .{ "BLAKE3_NO_SSE2", "1" },
    .{ "BLAKE3_NO_SSE41", "1" },
    .{ "BLAKE3_NO_AVX2", "1" },
    .{ "BLAKE3_NO_AVX512", "1" },
};

const X86Kernel = struct {
    name: []const u8,
    source: []const u8,
    /// Target features applied to this kernel's separate object.
    features: []const std.Target.x86.Feature,
};

/// Keep each runtime-dispatched x86 kernel in a separate object with its own ISA.
/// Upstream offers intrinsics and assembly as alternatives; this build uses intrinsics.
const x86_kernels = [_]X86Kernel{
    .{ .name = "sse2", .source = "c/blake3_sse2.c", .features = &.{.sse2} },
    // SSSE3 is required by _mm_shuffle_epi8 (c/blake3_sse41.c:31,40).
    .{ .name = "sse41", .source = "c/blake3_sse41.c", .features = &.{.sse4_1} },
    // .avx accompanies .avx2 for the vector ABI (c/blake3_avx2.c:236).
    .{ .name = "avx2", .source = "c/blake3_avx2.c", .features = &.{.avx2} },
    // The AVX-512 kernel also requires AVX512VL (c/blake3_avx512.c:1227).
    .{
        .name = "avx512",
        .source = "c/blake3_avx512.c",
        .features = &.{ .avx512f, .avx512vl },
    },
};

/// Upstream enables NEON explicitly; it is baseline on AArch64 (c/CMakeLists.txt:204-209).
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
    x86_intrinsics,
    neon,
    none,
    fn for_arch(arch: std.Target.Cpu.Arch, portable: bool) Simd {
        if (portable) return .none;
        return switch (arch) {
            // Upstream uses intrinsics on 32-bit x86 because its assembly is x86_64-only (c/README.md:302-304).
            .x86_64, .x86 => .x86_intrinsics,
            .aarch64 => .neon,
            // Upstream uses the portable core on other architectures (c/README.md:376-383).
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
    bundled,
    system,
};

/// Targets compiled by the default check step.
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
    /// Null in system mode, where this build has no artifact.
    c_lib: ?*std.Build.Step.Compile,
    /// Facade module, public or private to a matrix target.
    module: *std.Build.Module,
};

/// Name private matrix artifacts by target triple.
fn artifact_name(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    public: bool,
) []const u8 {
    if (public) return lib_name;
    const triple = target.result.zigTriple(b.allocator) catch @panic("unspellable target");
    return b.fmt("{s}-{s}", .{ lib_name, triple });
}

/// Matrix graphs use private modules because module names are registered globally.
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
        // Linkage selects this build's delivery or the installed library.
        const delivered = deliveredLinkage(target, linkage);

        // Translate the header shipped with this library.
        translate.addIncludePath(b.path("c"));
        if (delivered == .dynamic) {
            // Match upstream's DLL import macro for shared consumers (c/CMakeLists.txt:140-141).
            translate.defineCMacro("BLAKE3_DLL", "1");
        }
    } else {
        // Use pkg-config for both the installed header and library; mismatched headers can describe a different ABI.
        // Runtime dispatch is generated from this translation too.
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
    // Runtime dispatch and the facade must share the generated core module's loader types.
    if (runtime_loaded) {
        // Runtime mode uses the caller-loaded provider and links no native library.
        module.addImport("c", graph.createModule(b, translate, target, optimize));
    } else {
        // Keep the translated header private; publish only the facade module.
        module.addImport("c", translate.createModule());
        module.addImport("rt", graph.createCoreModule(b, target, optimize));
        if (c_lib) |lib| {
            module.linkLibrary(lib);
        } else {
            // Require pkg-config so the linked library matches the translated header.
            module.linkSystemLibrary(lib_name, .{
                .use_pkg_config = .force,
                .preferred_link_mode = linkage,
            });
        }
    }

    return .{ .c_lib = c_lib, .module = module };
}

/// Resolve each kernel against the caller's target with only its own ISA features.
/// Baseline CPU features keep runtime dispatch from executing unsupported instructions.
/// Keep `base` alive because `Query.fromTarget` retains its CPU-model pointer.
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

/// Compile each runtime-dispatched x86 kernel as its own target-specific object.
/// Keep the library core at the caller's baseline target.
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
        .link_libc = true,
        .pic = if (linkage == .dynamic) true else null,
    });
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

/// Compile the core and target-supported kernels.
/// Shared delivery requires a dynamic linker; unsupported targets are refused.
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
        // Upstream's SOVERSION 0 and VERSION 1.8.7 (c/CMakeLists.txt:150-155).
        .version = if (linkage == .dynamic) abi_version else null,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            // Shared libraries and their kernel objects require PIC.
            .pic = if (linkage == .dynamic) true else null,
        }),
    });
    const c_mod = c_lib.root_module;
    const flags = cUnitFlags(linkage);
    c_mod.addIncludePath(b.path("c"));

    // Upstream's DLL macros distinguish exported definitions from imports (c/blake3.h:9-14).
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
        // Keep the core and dispatcher at the requested target; kernels use separate targets.
        .x86_intrinsics => {
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

    // Leave optional oneTBB support disabled, as upstream does by default (c/CMakeLists.txt:20).
    c_lib.installHeader(b.path("c/blake3.h"), "blake3.h");

    return c_lib;
}

/// Compile the test and example roots for each target without running them.
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
    // Name matrix artifacts by target triple.
    const triple = cross_target.result.zigTriple(b.allocator) catch @panic("unspellable target");
    // System mode builds no artifact, so only bundled shared delivery needs this check.
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

/// Generate upstream's pkg-config metadata with a relocatable prefix.
/// Shared builds add the Windows DLL import macro to Cflags (c/CMakeLists.txt:139-145).
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
            if (linkage == .dynamic) " -DBLAKE3_DLL" else "",
        })),
        .lib,
        "pkgconfig/libblake3.pc",
    );
    b.getInstallStep().dependOn(&install.step);
}

/// Install upstream licence texts and fork provenance records under share/licenses/blake3/.
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

fn addMisuseRuns(b: *std.Build, misuse: *std.Build.Step.Compile, provider: std.Build.LazyPath) void {
    const step = b.step(
        "runtime-misuse",
        "Run runtime/misuse.zig after-load <provider>: the control that must " ++
            "succeed. The pre-load and linked-load modes must stop and are run " ++
            "and observed by the driver, not asserted here.",
    );
    const run = b.addRunArtifact(misuse);
    run.addArgs(&.{"after-load"});
    // Step.Run accepts the provider as a LazyPath argument, not an environment value.
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

    // Preserve each mode's default: static when bundled, dynamic when system-linked.
    const linkage: std.builtin.LinkMode = linkage_option orelse
        (if (library == .system) .dynamic else .static);

    // Runtime loading controls dispatch; linkage controls artifact delivery.
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

    // Keep the manifest and upstream C-library versions in sync.
    if (manifest_version.order(upstream_version) != .eq) {
        @panic("build.zig.zon .version no longer matches the version read out " ++
            "of c/blake3.h and c/CMakeLists.txt; see UPSTREAM.md");
    }

    const published = add_graph(b, target, optimize, portable, library, linkage, runtime_loaded, true);
    if (published.c_lib) |c_lib| b.installArtifact(c_lib);

    if (library == .bundled) {
        add_pkg_config(b, linkage);
        install_licence_records(b);
    }

    // The install step compiles the example but does not install it.
    const example = add_example(b, target, optimize, published.module, "blake3-smoke");
    b.getInstallStep().dependOn(&example.step);

    const run_example = b.addRunArtifact(example);
    if (b.args) |args| run_example.addArgs(args);
    b.step("smoke", "Run the deterministic example program").dependOn(&run_example.step);

    // Keep tests.zig as the root so Zig discovers its test blocks.
    const unit_tests = add_tests(b, target, optimize, published.module, "blake3-tests");
    b.step("test", "Run the behavioural tests").dependOn(&b.addRunArtifact(unit_tests).step);

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

/// Windows uses PE/COFF without an interpreter path; WASI has no dynamic loader.
fn targetHasDynamicLinker(target: std.Build.ResolvedTarget) bool {
    return target.result.os.tag == .windows or std.Target.DynamicLinker.kind(target.result.os.tag) != .none;
}

/// Refuse unsupported shared delivery; never substitute a static archive.
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
