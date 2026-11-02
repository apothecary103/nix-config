{
  description = "Silicon Bakery for NixOS: Asahi Linux, finished to behave like the Mac it runs on";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    apple-silicon = {
      url = "github:nix-community/nixos-apple-silicon";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      apple-silicon,
      ...
    }:
    let
      inherit (nixpkgs) lib;
      systems = [
        "aarch64-linux"
        "x86_64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # What an Apple Silicon NixOS system builds: nixpkgs with
      # nixos-apple-silicon's packages and these.
      target = nixpkgs.legacyPackages.aarch64-linux.appendOverlays [
        apple-silicon.overlays.default
        self.overlays.default
      ];
    in
    {
      lib = import ./lib { inherit lib; };

      overlays.default = import ./pkgs { };

      nixosModules = {
        # Everything: nixos-apple-silicon's Asahi support and Silicon Bakery on
        # top. Set hardware.siliconBakery = { enable = true; model = "..."; }.
        default = {
          imports = [
            apple-silicon.nixosModules.apple-silicon-support
            self.nixosModules.silicon-bakery
          ];
        };
        # Silicon Bakery alone, for systems that import nixos-apple-silicon
        # themselves.
        silicon-bakery = ./modules;
      };

      packages.aarch64-linux = {
        inherit (target.siliconBakery)
          libinput
          wlroots
          river
          kwim
          mesa
          hk-dispatch-bench
          ;
      };

      checks = forAllSystems (pkgs: import ./tests { inherit pkgs target; });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);
    };
}
