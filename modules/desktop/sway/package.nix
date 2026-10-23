{
  # The compositor is our fork of sway: nixpkgs' release with ./patches applied
  # in order. Upstream backports come first (numbered by when they landed),
  # then work of our own.
  flake.modules.nixos.base =
    { lib, pkgs, ... }:
    {
      programs.sway.package = pkgs.sway.override {
        sway-unwrapped = pkgs.sway-unwrapped.overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ lib.filesystem.listFilesRecursive ./patches;
        });
      };
    };
}
