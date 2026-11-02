# Silicon Bakery: nixos-apple-silicon's Asahi support (the flake's default
# module imports it), finished for one Mac at a time from that Mac's profile
# (profiles/<model>), so Linux behaves like the macOS it replaces.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.siliconBakery;
  bakery = import ../lib { inherit lib; };
in
{
  imports = [
    ./display.nix
    ./graphics.nix
    ./input.nix
    ./media.nix
  ];

  options.hardware.siliconBakery = {
    enable = lib.mkEnableOption "Silicon Bakery, Asahi Linux finished to behave like the Mac it runs on";

    model = lib.mkOption {
      type = lib.types.str;
      example = "Mac14,9";
      description = ''
        The Mac's model identifier (`sysctl hw.model` on macOS,
        /proc/device-tree/compatible on Linux names the board instead). It
        picks the profile in profiles/<model>; models with one: ${lib.concatStringsSep ", " bakery.models}.
      '';
    };

    profile = lib.mkOption {
      type = lib.types.attrs;
      default = bakery.profile cfg.model;
      defaultText = lib.literalExpression "silicon-bakery.lib.profile config.hardware.siliconBakery.model";
      description = ''
        What the Mac says about itself under macOS (tools/bakery-probe), with
        what was measured on Linux laid over it. Everything that follows the
        Mac's own numbers reads them from here.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    nixpkgs.overlays = [
      (import ../pkgs {
        threeFingerDragReleaseMs = cfg.profile.trackpad.measured.threeFingerDragReleaseMs or null;
      })
    ];

    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isAarch64 && pkgs.stdenv.hostPlatform.isLinux;
        message = "silicon-bakery is for Apple Silicon Macs running NixOS (aarch64-linux).";
      }
      {
        assertion = config.hardware.asahi.enable or false;
        message = "silicon-bakery builds on nixos-apple-silicon: import silicon-bakery.nixosModules.default, which brings it.";
      }
    ];
  };
}
