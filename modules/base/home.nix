{ inputs, username, ... }:

let
  pkgsCfg = import ../../pkgs { inherit inputs; };
in
{
  nixpkgs.overlays = pkgsCfg.overlays;

  programs.fish.enable = true;
  programs.nix-index-database.comma.enable = true;

  nix.settings.trusted-users = [ username ];

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs username; };
    users.${username}.imports = pkgsCfg.homeModules ++ [ ../../home/base ];
    # backupFileExtension = "backup";
  };
}
