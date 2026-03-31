{ config, pkgs, inputs, username, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/base
    ../../modules/nixos
    inputs.home-manager.nixosModules.home-manager
    inputs.apple-silicon.nixosModules.apple-silicon-support
  ];

  networking.hostName = "frieren";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = false;
  boot.kernelParams = [ 
    "appledrm.show_notch=1" 
  ];

  # NOTE: You must have the firmware files extracted on your EFI partition
  hardware.asahi.peripheralFirmwareDirectory = inputs.asahi-firmware;
  
  time.timeZone = "Europe/Vilnius";

  # nix.settings.cores = 0; # use all available cores

  hardware.bluetooth.enable = true;
  services.blueman.enable = true;

  programs.zsh.enable = true;

  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-gnome
      pkgs.xdg-desktop-portal-gtk
    ];
    config = {
      common.default = [ "gnome" "gtk" ];
      niri.default = [ "gnome" "gtk" ];
    };
  };

  programs.dconf.enable = true;

  users.users.${username} = {
    isNormalUser = true;
    description = username;
    shell = pkgs.zsh;
    extraGroups = [ "wheel" "networkmanager" "video" ];
  };
  nix.settings.trusted-users = [ username ];

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs username; hostname = "frieren"; };
    users.${username} = import ../../home/default.nix;
  };

  system.stateVersion = "25.11";
}
