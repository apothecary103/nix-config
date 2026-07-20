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
  };

  outputs = inputs @ { self, nixpkgs, darwin, home-manager, ... }:
  let
    username = "apothecary";
  in {
    darwinConfigurations."fern" = darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      specialArgs = { inherit inputs username; };
      modules = [ ./modules/darwin ./home/darwin ];
    };

    nixosConfigurations."frieren" = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      specialArgs = { inherit inputs username; };
      modules = [ ./modules/nixos ./home/nixos ];
    };
  };
}
