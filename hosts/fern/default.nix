{ config, pkgs, inputs, username, ... }:

{
  imports = [
    ../../modules/base
    ../../modules/darwin
    inputs.home-manager.darwinModules.home-manager
  ];

  networking.hostName = "fern";

  users.users.${username} = {
    name = username;
    home = "/Users/${username}";
    description = username;
  };
  nix.settings.trusted-users = [ username ];

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs username; hostname = "fern"; };
    users.${username} = import ../../home/default.nix;
  };

  system.stateVersion = 6;
}
