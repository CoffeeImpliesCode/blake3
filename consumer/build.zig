const std = @import("std");

/// Verifies `dep.module("blake3")` against upstream digests in `zig build run`.
/// Forwards linkage, portability, system and runtime options; runtime mode accepts `--provider <path>` or `BLAKE3_TEST_PROVIDER`.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const linkage = b.option(
        std.lang.LinkMode,
        "linkage",
        "Which delivery of libblake3 the dependency builds: a static archive or " ++
            "a real shared object carrying upstream's soname. In system mode " ++
            "this graph builds no artifact, so the option names the kind of " ++
            "installed library to bind to instead. Forwarded to the library's " ++
            "own -Dlinkage. Left unset, the option is not passed on and the " ++
            "library's own default decides.",
    );
    const portable = b.option(
        bool,
        "portable",
        "Build the dependency with the scalar core only: no SIMD kernel is " ++
            "linked in and upstream's BLAKE3_NO_* macros are defined, while " ++
            "the facade, the consumer program and the expected digests are " ++
            "unchanged. The same published vectors then have to agree through " ++
            "blake3_portable.c alone. No effect in system mode, where no C is " ++
            "compiled. Forwarded to the library's own -Dportable. Left unset, " ++
            "the option is not passed on and the library's own default decides.",
    );
    const system = b.option(
        bool,
        "system",
        "Build the dependency against an installed libblake3 and its installed " ++
            "blake3.h instead of compiling c/ from this repository. Nothing is " ++
            "built or installed by this package in that mode, so the same " ++
            "program and the same published digests come from the provider on " ++
            "the machine. Forwarded to the library's own -Dsystem. Left unset, " ++
            "the option is not passed on and the library's own default decides.",
    );
    const runtime = b.option(
        bool,
        "runtime",
        "Build the dependency with its runtime-loading dispatch, so the facade " ++
            "reaches the native entry points through one process-lifetime table " ++
            "that an explicit load(source) fills instead of through a link line, " ++
            "and the module links no archive. Forwarded to the library's own " ++
            "-Druntime, independently of -Dlinkage. Left unset, the option is " ++
            "not passed on and the library's own default decides.",
    );

    const dep = b.dependency("blake3", .{
        .target = target,
        .optimize = optimize,
        .linkage = linkage,
        .portable = portable,
        .system = system,
        .runtime = runtime,
    });

    // The library module declares its C requirement; do not mask a missing declaration here.
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("blake3", dep.module("blake3"));

    const exe = b.addExecutable(.{
        .name = "blake3-consumer",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    // Forward run arguments for runtime mode; without a provider path, `main.zig` reads `BLAKE3_TEST_PROVIDER`.
    run_exe.addPassthruArgs();
    const run_step = b.step("run", "Build and run the consumer program");
    run_step.dependOn(&run_exe.step);
}
