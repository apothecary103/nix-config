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

    boot.loader.limine.enable = true;
    boot.loader.efi.canTouchEfiVariables = false;
    boot.kernelParams = [
      "appledrm.show_notch=1"
    ];
    hardware.asahi.peripheralFirmwareDirectory = inputs.asahi-firmware;
    hardware.asahi.enable = true;

    system.stateVersion = "25.11";
  };

  flake.nixosConfigurations.frieren = inputs.nixpkgs.lib.nixosSystem {
    modules = [ config.flake.modules.nixos."hosts/frieren" ];
  };
}
