{ username, ... }:
let
  nix =
    {
      pkgs,
      lib,
      ...
    }:
    {
      nixpkgs.config.allowUnfree = true;

      nix = {
        enable = true;
        package = pkgs.nix;

        settings = {
          experimental-features = [
            "nix-command"
            "flakes"
          ];

          auto-optimise-store = true;
          trusted-users = [ username ];

          # Every flake reference here is a full URL, so the only thing the
          # registry does is fetch github:NixOS/flake-registry on each nix run.
          flake-registry = "";

          extra-substituters = [ "https://nix-community.cachix.org" ];
          extra-trusted-public-keys = [
            "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
          ];
        };

        gc = {
          automatic = lib.mkDefault true;
          options = lib.mkDefault "--delete-older-than 7d";
        };
      };
    };
in
{
  flake.modules.nixos.base = nix;
  flake.modules.darwin.base = nix;
}
