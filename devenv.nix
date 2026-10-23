# SPDX-License-Identifier: CC0-1.0 OR Apache-2.0 OR Apache-2.0 WITH LLVM-exception
#
{ pkgs, lib, config, inputs, ... }:

let
  # Select Zig 0.16; the assertion below checks the resolved version.
  zig = pkgs.zig_0_16;

  mk = linkage: pkgs.callPackage ./package.nix {
    inherit zig linkage;
  };

  # Use a string path so Nix does not copy the working tree into its store.
  sdkRoot = builtins.toString ./.;
  sdkRootArg = lib.escapeShellArg sdkRoot;

  # Tasks require caches outside the repository, selected from caller env or fallbacks.
  cacheDir = "$ZIG_LOCAL_CACHE_DIR/blake3";
  globalCacheDir = "$ZIG_GLOBAL_CACHE_DIR";
  installPrefix = "$ZIG_LOCAL_CACHE_DIR/blake3-prefix";

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
    default = mk "static";
  };

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

  # Every task starts from the SDK root; only sdk:build sets an install prefix.
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