# SPDX-License-Identifier: CC0-1.0 OR Apache-2.0 OR Apache-2.0 WITH LLVM-exception
#
# Canonical development shell. Three properties matter:
#
#   * packages holds tools only. The SDK package is not a shell input, so
#     entering the shell never builds it.
#   * outputs.static and outputs.shared are lazy: `devenv build outputs.static`
#     and `devenv build outputs.shared` call the same package.nix the flake
#     calls. That is the packaging route, not an echoing script.
#   * every task body starts from this module's own directory and keeps what it
#     generates under the external cache the caller named. devenv runs a task
#     with the caller's working directory, and that directory is not this SDK:
#     it holds `devenv.lock` and `.devenv/` and none of `build.zig`.
#
# Nothing here hard-codes a host path or reads the environment at eval time.
# Not evaluated or entered by its author; README.md's rows are
# PENDING-VERIFICATION until the driver runs them.
{ pkgs, lib, config, inputs, ... }:

let
  # nixpkgs derives this attribute name from "0.16.0". The assertion below stops
  # a nixpkgs bump from silently moving this SDK onto another compiler.
  zig = pkgs.zig_0_16;

  mk = linkage: pkgs.callPackage ./package.nix {
    inherit zig linkage;
  };

  # This module's own directory, and the shell-quoted form every body below
  # starts from.
  #
  # `./.` in an expression is relative to the file that contains it, so this is
  # the SDK root however devenv was invoked. It is `builtins.toString` and not
  # `"${./.}"` deliberately: interpolating a path copies it into the read-only
  # Nix store, which here would be a second, frozen copy of the whole SDK
  # rather than the working tree an integrity record, an edit and the consumer's
  # own path dependency are about.
  sdkRoot = builtins.toString ./.;
  sdkRootArg = lib.escapeShellArg sdkRoot;

  # The build cache and the one install prefix live beneath `ZIG_LOCAL_CACHE_DIR`,
  # the workspace's canonical local cache variable, so a caller's own exported
  # value is used exactly as it stands. The global cache is named too, because a
  # `zig build` that is given no `--global-cache-dir` resolves one of its own and
  # this file does not know where that is. Never this repository, never a volume
  # this file knows nothing about. The paths are assembled here, in Nix, and
  # expanded by the shell at run time, because the location is the caller's
  # rather than this file's.
  cacheDir = "$ZIG_LOCAL_CACHE_DIR/blake3";
  globalCacheDir = "$ZIG_GLOBAL_CACHE_DIR";
  installPrefix = "$ZIG_LOCAL_CACHE_DIR/blake3-prefix";

  # The preamble every task below opens with: this module's own directory, then
  # both caches, then a refusal rather than a guess. An exported
  # `ZIG_LOCAL_CACHE_DIR` or `ZIG_GLOBAL_CACHE_DIR` is used unchanged; either
  # missing one is filled from `XDG_CACHE_HOME`, then from `TMPDIR`. Every check
  # is here, in the body, before the compiler is reached: `devenv tasks run
  # --mode single <name>` does not run `enterShell`, so a task that relied on it
  # would be silently building against this SDK's own `.zig-cache` otherwise.
  # None of these fallbacks is a literal `/tmp`, `/var/tmp`, an NFS mount or a
  # path inside this repository.
  preamble = ''
    set -eu
    cd ${sdkRootArg}
    : "''${ZIG_LOCAL_CACHE_DIR:=''${XDG_CACHE_HOME:-''${TMPDIR:-}}}"
    : "''${ZIG_LOCAL_CACHE_DIR:?blake3 devenv: ZIG_LOCAL_CACHE_DIR is unset, and neither XDG_CACHE_HOME nor TMPDIR names a cache location}"
    : "''${ZIG_GLOBAL_CACHE_DIR:=''${XDG_CACHE_HOME:-''${TMPDIR:-}}}"
    : "''${ZIG_GLOBAL_CACHE_DIR:?blake3 devenv: ZIG_GLOBAL_CACHE_DIR is unset, and neither XDG_CACHE_HOME nor TMPDIR names a cache location}"
  '';
in
{
  packages = [
    zig
    pkgs.pkg-config
    pkgs.git
  ];

  outputs = {
    static = mk "static";
    shared = mk "dynamic";
    # static is this SDK's native policy.
    default = mk "static";
  };

  # The same fill-in at shell entry, so an interactive `zig build` and the tasks
  # below agree about where output goes. A value the caller already exported is
  # kept; only an unset variable is completed, and a shell that names no location
  # at all is told so rather than handed one. Nothing here is what makes a task
  # work: `preamble` above repeats all of it.
  enterShell = ''
    : "''${ZIG_LOCAL_CACHE_DIR:=''${XDG_CACHE_HOME:-''${TMPDIR:-}}}"
    : "''${ZIG_GLOBAL_CACHE_DIR:=''${XDG_CACHE_HOME:-''${TMPDIR:-}}}"
    if [ -n "''${ZIG_LOCAL_CACHE_DIR:-}" ] && [ -n "''${ZIG_GLOBAL_CACHE_DIR:-}" ]; then
      export ZIG_LOCAL_CACHE_DIR ZIG_GLOBAL_CACHE_DIR
      mkdir -p "$ZIG_LOCAL_CACHE_DIR" "$ZIG_GLOBAL_CACHE_DIR"
      echo "blake3 devenv: cache $ZIG_LOCAL_CACHE_DIR/blake3, global cache $ZIG_GLOBAL_CACHE_DIR, install prefix $ZIG_LOCAL_CACHE_DIR/blake3-prefix"
    else
      echo "blake3 devenv: ZIG_LOCAL_CACHE_DIR and ZIG_GLOBAL_CACHE_DIR are unset and neither XDG_CACHE_HOME nor TMPDIR names a location, so no cache or prefix is chosen here; a task refuses to run until one of them is set." >&2
    fi
  '';

  # Namespaced: devenv puts task names on one list, and a bare `build` or `test`
  # would collide with the ordinary shell commands of the same name. Every body
  # opens with `preamble`, so it runs in this SDK's own directory, resolves both
  # caches there, and reaches the compiler with `-j8`, `--summary all` and both
  # cache directories already written out rather than wherever the caller stood
  # or whatever `zig` would have picked for itself.
  #
  # Only `sdk:build` carries `--prefix`. A bare `zig build` runs the install
  # step, and `build.zig:1359,1378,1467` attach the artifact, the public header,
  # `libblake3.pc`, the licence records and the example to it, so without a
  # prefix that task would write `zig-out/` into this repository. `test`
  # (`build.zig:1392`), `runtime-test` (`build.zig:1445-1465`) and `check`
  # (`build.zig:1472-1483`) depend on no install step and install nothing, so
  # those bodies get caches and no prefix.
  tasks = {
    "sdk:build" = {
      description = "zig build - compile and install under the caller's external prefix";
      exec = ''
        ${preamble}
        zig build --cache-dir "${cacheDir}" --global-cache-dir "${globalCacheDir}" --prefix "${installPrefix}" -Doptimize=Debug -j8 --summary all
      '';
    };
    "sdk:test" = {
      description = "zig build test - replay upstream's published vectors";
      exec = ''
        ${preamble}
        zig build test --cache-dir "${cacheDir}" --global-cache-dir "${globalCacheDir}" -Doptimize=Debug -j8 --summary all
      '';
    };
    "sdk:check" = {
      description = "zig build check - the six-target compile-only matrix";
      exec = ''
        ${preamble}
        zig build check --cache-dir "${cacheDir}" --global-cache-dir "${globalCacheDir}" -Doptimize=Debug -j8 --summary all
      '';
    };
    "sdk:runtime-test" = {
      description = "zig build runtime-test -Druntime=true; needs BLAKE3_TEST_PROVIDER and BLAKE3_TEST_ALIEN exported";
      exec = ''
        ${preamble}
        test -n "''${BLAKE3_TEST_PROVIDER:-}" || { echo "export BLAKE3_TEST_PROVIDER first" >&2; exit 1; }
        test -n "''${BLAKE3_TEST_ALIEN:-}" || { echo "export BLAKE3_TEST_ALIEN first" >&2; exit 1; }
        exec zig build runtime-test --cache-dir "${cacheDir}" --global-cache-dir "${globalCacheDir}" -Druntime=true -Doptimize=Debug -j8 --summary all
      '';
    };
  };

  assertions = [
    {
      assertion = zig.version == "0.16.0";
      message = "This SDK targets Zig 0.16.0 (pkgs.zig_0_16); got ${zig.version}.";
    }
  ];
}