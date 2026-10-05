const std = @import("std");

/// A package that consumes `blake3` from outside.
///
/// This exists to prove one thing: that a dependent needs only
/// `dep.module("blake3")` and gets a working, correctly linked library. If the
/// facade module stopped carrying its C artifact, or the translated header
/// stopped matching the C source, this would stop building or stop producing
/// the digests below, and nothing inside the library would notice.
///
/// Run it with `zig build run`. It exits non-zero if any digest disagrees with
/// the answer upstream publishes for that exact input, so it is a check and
/// not a demo.
///
/// The library's own four delivery axes are forwarded here rather than
/// reinterpreted, and they are independent of one another. `-Dlinkage` names
/// which artifact the dependency builds and installs, or in system mode which
/// kind of *installed* library to bind to; `-Dportable` selects the scalar core
/// instead of a dispatched SIMD kernel; `-Dsystem` selects the installed
/// library and its installed header instead of compiling `c/` at all;
/// `-Druntime` names how the facade reaches the library, through a link line
/// or through the one process-lifetime table an explicit `load(source)` fills.
/// `src/main.zig` is written for both shapes, so each of the combinations is
/// one real program and not a compile-only configuration: under
/// `blake3.runtime_loaded` it names a provider with `--provider <path>` or
/// `BLAKE3_TEST_PROVIDER`, loads it once, and the same published digests
/// follow.
///
/// `-Dportable` and `-Dsystem` are the two axes without which the published
/// module cannot be exercised from outside at all: they are where the
/// translated header, the macros and the artifact all differ from the
/// default graph. Declaring them is also what makes `b.option` do its job —
/// an undeclared `-D` is a configuration error rather than a flag the build
/// system silently drops, so a caller who passed one and saw it ignored would
/// have been told so.
///
/// None of the four is given a default here. A `null` user-input option is not
/// passed on to the dependency at all (`lib/std/Build.zig:430-437`, `:569-581`),
/// so a caller who names none gets the library's own defaults and this package
/// keeps no second copy of them to drift away from.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const linkage = b.option(
        std.builtin.LinkMode,
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

    // No `link_libc` here on purpose. The C requirement belongs to the library
    // module, which carries it; a dependent states its own, and this program
    // needs nothing beyond what the library already brings. Adding it here
    // would hide a library that forgot to declare it.
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
    // Forwarded so `zig build run -Druntime=true -- --provider <path>` reaches
    // `src/main.zig`, which reads exactly that and otherwise falls through to
    // `BLAKE3_TEST_PROVIDER`. With no arguments this is inert, so a linked run
    // is unchanged.
    if (b.args) |args| run_exe.addArgs(args);
    const run_step = b.step("run", "Build and run the consumer program");
    run_step.dependOn(&run_exe.step);
}
