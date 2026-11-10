{
  description = "yanms: Minecraft modpack servers on NixOS, on an overlay of the read-only pack, with a console FIFO and restic backups";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    flake-parts,
    self,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} ({lib, ...}: let
      importPackages = import ./lib/import-packages.nix {inherit lib;};

      mkPackages = pkgs: let
        sources = pkgs.callPackage ./sources/generated.nix {};
        mkForgeServer = pkgs.callPackage ./packages/_lib/mk-forge-server.nix {inherit sources;};
      in
        importPackages {
          inherit sources;
          nixpkgs = pkgs;
          packages = ./packages;
          extraArguments = {inherit mkForgeServer;};
        };

      # nvfetcher entries with `passthru.mod`: <loader>.<mc-version>.<name> = the jar.
      mkMods = pkgs:
        lib.pipe (pkgs.callPackage ./sources/generated.nix {}) [
          (lib.filterAttrs (_: v: v ? mod))
          lib.attrValues
          (builtins.groupBy (v: v.mod))
          (lib.mapAttrs (_: byLoader:
            lib.mapAttrs (_: byVersion: lib.listToAttrs (map (v: lib.nameValuePair v.name v.src) byVersion))
            (builtins.groupBy (v: v.mc-version) byLoader)))
        ];
    in {
      # The servers run on Linux; macOS gets the formatter and the nvfetcher shell.
      systems = ["aarch64-linux" "x86_64-linux" "aarch64-darwin"];

      perSystem = {
        pkgs,
        system,
        ...
      }: {
        packages = lib.optionalAttrs (lib.hasSuffix "-linux" system) (mkPackages pkgs);

        checks = lib.optionalAttrs (lib.hasSuffix "-linux" system) {
          module = import ./tests/module.nix {
            inherit pkgs;
            module = self.nixosModules.yanms;
          };
        };

        devShells.default = pkgs.mkShellNoCC {
          packages = [pkgs.nvfetcher];
        };

        formatter = pkgs.alejandra;
      };

      flake = {
        lib.jvmFlags = import ./lib/jvm-flags.nix;

        overlays.default = final: _prev:
          mkPackages final
          // {
            minecraftMods = mkMods final;
            mkForgeServer = final.callPackage ./packages/_lib/mk-forge-server.nix {
              sources = final.callPackage ./sources/generated.nix {};
            };
          };

        nixosModules = {
          # The module alone.
          yanms = ./modules/yanms.nix;

          default = {
            imports = [self.nixosModules.yanms];
            nixpkgs.overlays = [self.overlays.default];
          };
        };
      };
    });
}
