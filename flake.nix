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
    apple-silicon.url = "github:tpwrules/nixos-apple-silicon";
    awww.url = "git+https://codeberg.org/LGFae/awww";
    catppuccin.url = "github:catppuccin/nix";
    hyprland.url = "github:hyprwm/Hyprland";
    asahi-firmware = {
      url = "path:/home/apothecary/.config/asahi-firmware";
      flake = false;
    };
  };

  outputs = inputs @ { self, nixpkgs, darwin, home-manager, apple-silicon, awww, catppuccin, nixpkgs-stable, ... }:
  let
    username = "apothecary";
  in {
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
