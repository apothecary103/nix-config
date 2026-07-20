{
  description = "My Nix Configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-25.11";
    darwin = {
      url = "github:lnl7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };
    apple-silicon.url = "github:tpwrules/nixos-apple-silicon";
    asahi-firmware = {
      url = "git+ssh://git@codeberg.org/frieren/asahi-firmware?ref=main";
      flake = false;
    };
    helix.url = "github:helix-editor/helix";
    catppuccin.url = "github:catppuccin/nix";
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nvf.url = "github:notashelf/nvf";
    helium.url = "gitlab:ntgn/helium-flake";
    tetro-tui.url = "github:Strophox/tetro-tui";
    yazelix-zellij = {
      url = "github:luccahuguet/yazelix-zellij";
      flake = false;
    };
    emacs-overlay = {
      url = "github:nix-community/emacs-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      darwin,
      home-manager,
      ...
    }:
    let
      username = "apothecary";

      yaaglPackages = pkgs: pkgs.callPackage ./pkgs/yaagl { };
      teamspeak6-client = pkgs: pkgs.callPackage ./pkgs/teamspeak6-client { };
    in
    {
      packages.aarch64-darwin = (yaaglPackages nixpkgs.legacyPackages.aarch64-darwin) // {
        teamspeak6-client = teamspeak6-client nixpkgs.legacyPackages.aarch64-darwin;
      };
      packages.x86_64-darwin = yaaglPackages nixpkgs.legacyPackages.x86_64-darwin;

      darwinConfigurations."fern" = darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        specialArgs = { inherit inputs username; };
        modules = [ ./hosts/fern ];
      };

      nixosConfigurations."frieren" = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        specialArgs = { inherit inputs username; };
        modules = [ ./hosts/frieren ];
      };
    };
}
