{ username, ... }:
let
  clean = {
    enable = true;
    extraArgs = "--keep-since 7d --keep 5";
  };
in
{
  # The NixOS programs.nh module asserts against nix.gc.automatic also being on.
  flake.modules.nixos.base = {
    nix.gc.automatic = false;

    programs.nh = {
      enable = true;
      flake = "/home/${username}/nix-config";
      inherit clean;
    };
  };

  # Same overlap on darwin, just without an assertion guarding it.
  flake.modules.darwin.base.nix.gc.automatic = false;

  # nix-darwin has no programs.nh module of its own, so configure it through
  # home-manager instead; it drives cleanup via a launchd agent on macOS.
  flake.modules.homeManager.darwin =
    { config, ... }:
    {
      programs.nh = {
        enable = true;
        flake = "${config.home.homeDirectory}/nix-config";
        inherit clean;
      };
    };
}
