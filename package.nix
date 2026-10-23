# SPDX-License-Identifier: CC0-1.0 OR Apache-2.0 OR Apache-2.0 WITH LLVM-exception
#
{
  lib,
  stdenv,
  zig,
  linkage ? "static",
  optimize ? "ReleaseSafe",
}:

assert builtins.elem linkage [ "static" "dynamic" ];

assert stdenv.hostPlatform.system == stdenv.buildPlatform.system;

let
  src = lib.cleanSourceWith {
    src = ./.;
    name = "blake3-source";
    # Basename filters exclude build state at every depth.
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
  # Upstream library version (c/blake3.h:33).
  version = "1.8.7";

  inherit src;

  strictDeps = true;

  nativeBuildInputs = [ zig ];

  dontBuild = true;
  dontConfigure = true;
  doInstallCheck = false;
  dontAddPrefix = true;
  dontSetZigDefaultFlags = true;
  doCheck = false;
  # Prevent the Zig hook from adding a second check build.
  dontCheck = true;
  dontUseZigCheck = true;

  installPhase = ''
    runHook preInstall

    # Keep Zig caches outside the read-only source tree.
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
    # meta.license selects the grant used for this output.
    # See FORK-LICENSE.md and NOTICE.md for the full choice.
    license = "Apache-2.0 WITH LLVM-exception";
    licenseFile = "LICENSE_A2LLVM";
    platforms = lib.platforms.all;
  };
}