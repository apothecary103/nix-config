{
  pkgs,
  inputs,
  username,
  ...
}:

let
  pkgsCfg = import ../../pkgs { inherit inputs; };
in
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/base
    ../../modules/nixos
    inputs.home-manager.nixosModules.home-manager
    inputs.apple-silicon.nixosModules.apple-silicon-support
    inputs.nix-index-database.nixosModules.default
  ];

  nixpkgs.overlays = pkgsCfg.overlays;

  networking.hostName = "frieren";
  time.timeZone = "Europe/Vilnius";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = false;
  boot.kernelParams = [
    "appledrm.show_notch=1"
  ];
  hardware.asahi.peripheralFirmwareDirectory = inputs.asahi-firmware;

  nix.settings.cores = 0; # Use all available cores

  # Cachix
  nix.settings = {
    extra-substituters = [
      "https://nixos-apple-silicon.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nixos-apple-silicon.cachix.org-1:8psDu5SA5dAD7qA0zMy5UT292TxeEPzIz8VVEr2Js20="
    ];
  };


  programs.nix-index-database.comma.enable = true; 
  programs.fish.enable = true;
  programs.dconf.enable = true;

  environment.pathsToLink = [
    "/share/applications"
    "/share/xdg-desktop-portal"
  ];


  users.users.${username} = {
    isNormalUser = true;
    description = username;
    shell = pkgs.fish;
    extraGroups = [
      "wheel"
      "video"
      "input"
    ];
  };
  nix.settings.trusted-users = [ username ];

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = {
      inherit inputs username;
      hostname = "frieren";
    };

    users.${username} = {
      imports = pkgsCfg.homeModules ++ [
        ../../home/base
        ../../home/nixos
      ];
    };
  };

  system.stateVersion = "25.11";
}
