{ config, pkgs, inputs, username, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/base
    ../../modules/nixos
    ./apple-silicon-support
    inputs.home-manager.nixosModules.home-manager
  ];

  networking.hostName = "frieren";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = false;

  # NOTE: You must have the firmware files extracted on your EFI partition
  hardware.asahi.peripheralFirmwareDirectory = /home/apothecary/nix-config/hosts/frieren/firmware;

  users.users.${username} = {
    isNormalUser = true;
    description = username;
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
