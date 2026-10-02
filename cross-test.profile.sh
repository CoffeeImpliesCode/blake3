# cross-test profile for the blake3 package.
#
# `cross-test` finds this file by itself when it is run from the package root,
# and sources it as trusted Bash. It is configuration, not a test: everything
# below is a setting the harness already has a default for, written out so the
# gate this package is verified by can be read without reading the harness.
#
# The harness keeps everything that decides what actually runs. The command is
# `zig build test -Dtarget=TARGET` over this package's real build graph, the
# matrix is the published Zig 0.16.0 Tier 1/2 platform table, and QEMU-user,
# Wasmtime, Wine and native execution are chosen by the harness. Nothing here
# replaces a build step, names an artifact, or adds a `zig build` option.
#
# Deliberately absent, and why:
#
#   * CROSS_MATRIX and TARGETS. The matrix is the whole published table. A
#     profile that names a subset still exits zero when the subset is green,
#     which is a narrower gate wearing the same exit code.
#   * cross_build_command / cross_artifact. Those switch the harness out of
#     the standard build into an artifact profile with a hand-written command.
#     The point of this gate is that `zig build test` runs the package's own
#     Zig test binary, over upstream's own C, for the selected target.
#   * Any -D option. The harness owns -Dtarget and the output/cache/run
#     settings. This profile chooses no -Doptimize override, so its test
#     graph uses Debug; CROSS_BUILD_ARGS=(-Doptimize=ReleaseSafe) is accepted
#     for a separate mode. The six-target compile-only `check` matrix remains
#     a separate command.
#   * ZIG, CROSS_PREFIX, CROSS_CACHE_DIR or any other path. A profile that
#     names one host's compiler cache or output directory is not a package
#     file; it silently stops working on every other machine.
#   * CROSS_REQUIRE_RUNNERS=1. That flag fails a platform for having no runner
#     on this host. A platform whose runner is absent is already reported as
#     explicit `build_only` coverage, which is a fact and not a pass; demanding
#     a runner would report missing runtimes as broken targets.
#
# Top-level code is limited to variable definitions because the harness sources
# this file more than once per run and expects it to be idempotent.

# The build step `cross-test` runs: the package's own Zig test binary, for the
# target the harness selected. Not `check`, which runs nothing.
CROSS_BUILD_STEP=test

# Overall deadline for one target's compile and complete test run. The first
# full matrix compiled all 53 targets, but AArch64's Debug one-shot/streaming
# tests exceeded the 300-second per-test default under QEMU. Keep the full
# vectors and split-boundary cases; allow time for the unchanged tests.
CROSS_BUILD_TIMEOUT=3600

# Per individual Zig test case, not per binary. The observed 300-second
# timeouts are retained in the before-matrix receipts.
CROSS_TIMEOUT=1800