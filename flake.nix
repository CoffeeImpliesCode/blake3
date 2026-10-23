# SPDX-License-Identifier: CC0-1.0 OR Apache-2.0 OR Apache-2.0 WITH LLVM-exception
#
{
  description = "BLAKE3 1.8.7 C library, built from this repository's own c/ source and wrapped in Zig 0.16";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/c7def046b9a883d46974757852106483d741586f";

  outputs =
    { nixpkgs, ... }:
    let
      systems = nixpkgs.lib.systems.flakeExposed;

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
          default = mk "static";
        }
      );

      devShells = forAllSystems (
        pkgs: {
          default = pkgs.mkShell {
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