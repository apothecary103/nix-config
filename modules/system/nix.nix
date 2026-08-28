{ inputs, ... }:
let
  nix = {
    nixpkgs.config.allowUnfree = true;

    nix = {
      channel.enable = false;
      registry.nixpkgs.flake = inputs.nixpkgs;

      settings = {
        experimental-features = [
          "nix-command"
          "flakes"
        ];

        # The only indirect reference we use is pinned above, so the global
        # registry would only add an unpinned network fetch.
        flake-registry = "";

        extra-substituters = [ "https://nix-community.cachix.org" ];
        extra-trusted-public-keys = [
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        ];
      };
    };
  };
in
{
  flake.modules.nixos.base = {
    imports = [ nix ];
    nix.optimise = {
      automatic = true;
      dates = "weekly";
    };
  };

  flake.modules.darwin.base = {
    imports = [ nix ];
    nix.optimise = {
      automatic = true;
      interval = {
        Weekday = 7;
        Hour = 4;
        Minute = 15;
      };
    };
  };
}
