{ inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/base
    ../../modules/nixos
    inputs.apple-silicon.nixosModules.apple-silicon-support
  ];

  networking.hostName = "frieren";
  time.timeZone = "Europe/Vilnius";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = false;
  boot.kernelParams = [
    "appledrm.show_notch=1"
  ];
  hardware.asahi.peripheralFirmwareDirectory = inputs.asahi-firmware;

  nix.settings = {
    cores = 0; # 0 = use all available cores
    extra-substituters = [
      "https://nixos-apple-silicon.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nixos-apple-silicon.cachix.org-1:8psDu5SA5dAD7qA0zMy5UT292TxeEPzIz8VVEr2Js20="
    ];
  };

  programs.dconf.enable = true;

  environment.pathsToLink = [
    "/share/applications"
    "/share/xdg-desktop-portal"
  ];

  system.stateVersion = "25.11";
}
