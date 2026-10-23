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
      # Hardware video decode on the AVD block, as VideoToolbox does on macOS.
      # Experimental upstream; players fall back to software when it fails.
      avd.vaapi-support = true;
    };

    # This records the on-disk schema from the original installation. Do not
    # bump it when updating nixpkgs; only change it for a deliberate reinstall.
    system.stateVersion = "25.11";
  };

  flake.nixosConfigurations.frieren = inputs.nixpkgs.lib.nixosSystem {
    modules = [ config.flake.modules.nixos."hosts/frieren" ];
  };
}
