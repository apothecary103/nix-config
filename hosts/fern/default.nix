{
  inputs,
  username,
  ...
}:

{
  imports = [
    ../../modules/base
    ../../modules/darwin
    inputs.home-manager.darwinModules.home-manager
  ];

  nixpkgs.overlays = [
    inputs.emacs-overlay.overlays.default
  ];

  nix.settings = {
    substituters = [ "https://nix-community.cachix.org" ];
    trusted-public-keys = [ "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=" ];
  };

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
    extraSpecialArgs = {
      inherit inputs username;
      hostname = "fern";
    };

    users.${username} = {
      imports = [
        ../../home/base
        ../../home/darwin
      ];
    };
  };

  # home-manager.backupFileExtension = "backup";

  system.stateVersion = 6;
}
