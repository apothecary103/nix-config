{
  config,
  inputs,
  username,
  ...
}: let
  hm = homeModules: {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.${username}.imports = homeModules;
  };
in {
  flake.modules.darwin.base = {
    imports = [inputs.home-manager.darwinModules.home-manager];
    home-manager = hm [
      config.flake.modules.homeManager.base
      config.flake.modules.homeManager.darwin
    ];
  };

  flake.modules.nixos.base = {
    imports = [inputs.home-manager.nixosModules.home-manager];
    home-manager = hm [
      config.flake.modules.homeManager.base
      config.flake.modules.homeManager.linux
    ];
  };

  flake.modules.homeManager.base = {pkgs, ...}: {
    home.username = username;
    home.homeDirectory =
      if pkgs.stdenv.isDarwin
      then "/Users/${username}"
      else "/home/${username}";

    home.stateVersion = "26.05";
    programs.home-manager.enable = true;
  };
}
