{
  description = "Nix for macOS configuration";

  inputs = {
    # nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-25.11-darwin";
    nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    darwin = {
      # url = "github:lnl7/nix-darwin/nix-darwin-25.11";
      url = "github:lnl7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };
    # 1. Add Home Manager input (matching your version 25.11)
    home-manager = {
      # url = "github:nix-community/home-manager/release-25.11";
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };
  };

  outputs = inputs @ { self, nixpkgs-darwin, darwin, home-manager, ... }: 
  let
    username = "apothecary";
    system = "aarch64-darwin";
    hostname = "darwin";

    specialArgs = inputs // { inherit username hostname; };
  in {
    darwinConfigurations."${hostname}" = darwin.lib.darwinSystem {
      inherit system specialArgs;
      modules = [
        ./modules/nix-core.nix
        ./modules/system.nix
        ./modules/apps.nix
        ./modules/host-users.nix

        # 2. Add the Home Manager darwin module
        home-manager.darwinModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users."${username}" = {
            imports = [
              ./home.nix
            ];
          };
          
          # Optional: passes variables to home.nix
          home-manager.extraSpecialArgs = { inherit username; };
        }
      ];
    };
  };
}
