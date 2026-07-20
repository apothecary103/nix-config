{
  inputs,
  username,
  pkgs,
  ...
}:

let
  pkgsCfg = import ../../pkgs { inherit inputs; };
in
{
  imports = [
    ../../modules/base
    ../../modules/darwin
    inputs.home-manager.darwinModules.home-manager
    inputs.nix-index-database.darwinModules.default
  ];

  nixpkgs.overlays = pkgsCfg.overlays;

  nix.settings = {
    substituters = [ "https://nix-community.cachix.org" ];
    trusted-public-keys = [ "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=" ];
  };

  networking.hostName = "fern";

  programs.fish.enable = true;

  programs.nix-index-database.comma.enable = true; 

  environment.shells = with pkgs; [
    fish
  ];

  users.users.${username} = {
    name = username;
    home = "/Users/${username}";
    description = username;
    shell = pkgs.fish;
  };
  nix.settings.trusted-users = [ username ];

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = {
      inherit inputs username;
      hostname = "fern";
    };

    users.${username} = {
      imports = pkgsCfg.homeModules ++ [
        ../../home/base
        ../../home/darwin
      ];
    };
  };

  # home-manager.backupFileExtension = "backup";

  system.stateVersion = 6;
}
