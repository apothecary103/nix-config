{
  config,
  inputs,
  ...
}:
{
  flake.modules.nixos."hosts/frieren" = {
    imports = [
      config.flake.modules.nixos.base
      inputs.silicon-bakery.nixosModules.default
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

    # The panel's colour, the GPU's render node, the trackpad's macOS curves
    # and palm sizes, AVD decode and the kernel and Mesa patches, all from
    # this MacBook's profile (silicon-bakery/profiles/Mac14,9).
    hardware.siliconBakery = {
      enable = true;
      model = "Mac14,9";
    };

    # This records the on-disk schema from the original installation. Do not
    # bump it when updating nixpkgs; only change it for a deliberate reinstall.
    system.stateVersion = "25.11";
  };

  flake.nixosConfigurations.frieren = inputs.nixpkgs.lib.nixosSystem {
    modules = [ config.flake.modules.nixos."hosts/frieren" ];
  };
}
