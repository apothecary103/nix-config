{
  description = "My Nix Configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    darwin = {
      url = "github:lnl7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    awww.url = "git+https://codeberg.org/LGFae/awww";
    catppuccin.url = "github:catppuccin/nix";
  };

  outputs = inputs @ { self, nixpkgs, darwin, home-manager, awww, catppuccin, ... }:
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
