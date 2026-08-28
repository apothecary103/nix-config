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
    hardware.asahi.peripheralFirmwareDirectory = inputs.asahi-firmware;
    hardware.asahi.enable = true;

    # This records the on-disk schema from the original installation. Do not
    # bump it when updating nixpkgs; only change it for a deliberate reinstall.
    system.stateVersion = "25.11";
  };

  flake.nixosConfigurations.frieren = inputs.nixpkgs.lib.nixosSystem {
    modules = [ config.flake.modules.nixos."hosts/frieren" ];
  };
}
