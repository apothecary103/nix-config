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

    nix.settings = {
      extra-substituters = [
        "https://nixos-apple-silicon.cachix.org"
      ];
      extra-trusted-public-keys = [
        "nixos-apple-silicon.cachix.org-1:8psDu5SA5dAD7qA0zMy5UT292TxeEPzIz8VVEr2Js20="
      ];
    };

    system.stateVersion = "25.11";
  };

  flake.nixosConfigurations.frieren = inputs.nixpkgs.lib.nixosSystem {
    modules = [ config.flake.modules.nixos."hosts/frieren" ];
  };
}
