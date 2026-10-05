# SPDX-License-Identifier: CC0-1.0 OR Apache-2.0 OR Apache-2.0 WITH LLVM-exception
#
# Entry point. Both variants are the same package.nix derivation, called twice.
# No formatter attribute: pkgs.zig_0_16 is a compiler, not a formatter package.
#
# flake.lock is the driver's to generate from observed evaluation.
# Status: not evaluated or built by its author.
{
  description = "BLAKE3 1.8.7 C library, built from this repository's own c/ source and wrapped in Zig 0.16";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/c7def046b9a883d46974757852106483d741586f";

  outputs =
    { nixpkgs, ... }:
    let
      systems = nixpkgs.lib.systems.flakeExposed;

      # One imported package set per system. Every output below is built from
      # it, so the two variants and the development shell cannot resolve
      # different `zig`, `stdenv` or dependency values.
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (
        pkgs:
        let
          mk = linkage:
            pkgs.callPackage ./package.nix {
              zig = pkgs.zig_0_16;
              inherit linkage;
            };
        in
        {
          static = mk "static";
          shared = mk "dynamic";
          # static is this SDK's native policy.
          default = mk "static";
        }
      );

      devShells = forAllSystems (
        pkgs: {
          default = pkgs.mkShell {
            # Tools only. The SDK package is not a shell input, so entering the
            # shell never builds it; `nix build .#static` does that on demand.
            packages = [
              pkgs.zig_0_16
              pkgs.pkg-config
              pkgs.git
            ];
          };
        }
      );
    };
}