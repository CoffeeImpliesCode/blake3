# SPDX-License-Identifier: CC0-1.0 OR Apache-2.0 OR Apache-2.0 WITH LLVM-exception
#
# One source-built derivation. flake.nix and devenv.nix both call this with
# pkgs.callPackage; the linkage variants live in those entry points, not here.
#
# The build is this repository's own `zig build install` over this repository's
# own c/. The native artifact, its headers, lib/pkgconfig/libblake3.pc and
# share/licenses/blake3/ are written by the build graph; this file does not
# reproduce any of them.
#
# Status: not evaluated or built by its author. README.md's packaging rows are
# PENDING-VERIFICATION until the driver runs them.
{
  lib,
  stdenv,
  zig,
  # static is what `zig build` produced before -Dlinkage existed.
  linkage ? "static",
  optimize ? "ReleaseSafe",
}:

assert builtins.elem linkage [ "static" "dynamic" ];

# No cross-compilation here. A remote *native* builder is fine: this compares
# the two platforms, it does not consult the evaluator's host.
assert stdenv.hostPlatform.system == stdenv.buildPlatform.system;

let
  src = lib.cleanSourceWith {
    src = ./.;
    name = "blake3-source";
    # Matched on the basename, so the rule holds at every depth: consumer/
    # .zig-cache, consumer/zig-out and a nested `result` are excluded by the
    # same names as the top-level ones. `result-*` and `.jj` are build and
    # version-control state too. Every source, fixture and licence file stays.
    filter = path: _type:
      let name = baseNameOf (toString path);
      in !(lib.elem name [
        ".git"
        ".jj"
        ".hg"
        ".svn"
        ".direnv"
        ".devenv"
        ".devenv.flake.nix"
        ".devenv.flakes"
        ".zig-cache"
        "zig-cache"
        "zig-out"
        "zig-pkg"
      ])
      && name != "result"
      && !(lib.hasPrefix "result-" name);
  };
in
stdenv.mkDerivation {
  pname = "blake3";
  # c/blake3.h:33; build.zig checks build.zig.zon against it at configure time.
  version = "1.8.7";

  inherit src;

  strictDeps = true;

  nativeBuildInputs = [ zig ];

  # An explicit install-only phase: build.zig.install already does the work, and
  # the hook's own build phase would compile a second variant with default flags.
  dontBuild = true;
  dontConfigure = true;
  # Not dontInstall: that would disable the installPhase below.
  doInstallCheck = false;
  dontAddPrefix = true;
  dontSetZigDefaultFlags = true;
  doCheck = false;
  # `dontCheck` is the conventional guard; `dontUseZigCheck` is the flag the
  # hook itself reads, and without it the hook substitutes `zig build test` —
  # a second, differently-flagged build inside this one.
  dontCheck = true;
  dontUseZigCheck = true;

  installPhase = ''
    runHook preInstall

    # Caches under the Nix-provided TMPDIR, outside the unpacked source tree,
    # which is read-only in the sandbox.
    export ZIG_LOCAL_CACHE_DIR="$TMPDIR/blake3-zig-local"
    export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/blake3-zig-global"
    mkdir -p "$ZIG_LOCAL_CACHE_DIR" "$ZIG_GLOBAL_CACHE_DIR"

    zig build install \
      --prefix "$out" \
      -j"''${NIX_BUILD_CORES:-1}" \
      -Doptimize=${optimize} \
      -Dcpu=baseline \
      -Dlinkage=${linkage}

    runHook postInstall
  '';

  passthru = {
    inherit linkage;
  };

  meta = {
    description = "BLAKE3 cryptographic hash function, C library built from this repository's c/ source";
    longDescription = ''
      BLAKE3 is a cryptographic hash function: a regular hash, a PRF/MAC, a KDF
      and an XOF, one algorithm with no variants. This package compiles
      upstream's own C sources from this repository's c/ directory, compiles the
      SIMD kernels the target architecture has as one object per instruction set,
      and publishes a Zig facade over the translated public header.
    '';
    # This tree offers a three-way choice; meta.license takes one identifier.
    # LICENSE_A2LLVM is the branch this output is distributed under; the full
    # choice is in FORK-LICENSE.md and NOTICE.md.
    license = "Apache-2.0 WITH LLVM-exception";
    licenseFile = "LICENSE_A2LLVM";
    platforms = lib.platforms.all;
  };
}