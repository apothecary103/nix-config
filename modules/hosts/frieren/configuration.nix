{
  config,
  inputs,
  ...
}:
{
  flake.modules.nixos."hosts/frieren" = {
    imports = [
      config.flake.modules.nixos.base
      inputs.apple-silicon.nixosModules.apple-silicon-support
    ];

    networking.hostName = "frieren";
    time.timeZone = "Europe/Vilnius";

    boot = {
      loader = {
        limine.enable = true;
        efi.canTouchEfiVariables = false;
      };
      kernelParams = [ "appledrm.show_notch=1" ];
    };
    hardware.asahi = {
      enable = true;
      peripheralFirmwareDirectory = inputs.asahi-firmware;
    };

    # This records the on-disk schema from the original installation. Do not
    # bump it when updating nixpkgs; only change it for a deliberate reinstall.
    system.stateVersion = "25.11";
  };

  # The LUKS + btrfs layout (disko.nix), installed from a live environment by
  # frieren-install. The Asahi image (image.nix) is nixosConfigurations.frieren.
  flake.nixosConfigurations.frieren-luks = inputs.nixpkgs.lib.nixosSystem {
    modules = [ config.flake.modules.nixos."hosts/frieren" ];
  };
}
