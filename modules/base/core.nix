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
      # enable flakes globally
      experimental-features = [
        "nix-command"
        "flakes"
      ];

      auto-optimise-store = true;
    };

    # do garbage collection weekly to keep disk usage low
    gc = {
      automatic = lib.mkDefault true;
      options = lib.mkDefault "--delete-older-than 7d";
    };
  };
}
