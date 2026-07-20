{ username, ... }:
{
  # nixpkgs ships a native programs.nh module for NixOS (root-level systemd
  # timer, so it can also reap old /nix/var/nix/profiles/system generations).
  # It asserts against nix.gc.automatic also being on, so turn that off here.
  flake.modules.nixos.base = {
    nix.gc.automatic = false;

    programs.nh = {
      enable = true;
      flake = "/home/${username}/nix-config";
      clean = {
        enable = true;
        extraArgs = "--keep-since 7d --keep 5";
      };
    };
  };

  # nix-darwin has no programs.nh module of its own, so configure it through
  # home-manager instead; it drives cleanup via a launchd agent on macOS.
  flake.modules.homeManager.darwin = {
    programs.nh = {
      enable = true;
      flake = "/Users/${username}/nix-config";
      clean = {
        enable = true;
        extraArgs = "--keep-since 7d --keep 5";
      };
    };
  };
}
