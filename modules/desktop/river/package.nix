{
  # The compositor is river with ./patches/river applied in order, then wrapped
  # with the settings those patches read. nixpkgs' river module still means
  # river-classic, but takes the new river as its package: it brings the
  # session file, portals and the rest of a wayland session.
  flake.modules.nixos.base =
    { lib, pkgs, ... }:
    {
      programs.river-classic = {
        enable = true;
        package = pkgs.river.overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ lib.filesystem.listFilesRecursive ./patches/river;
          nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.makeWrapper ];
          # Vulkan is the only wlroots renderer that applies an output colour
          # transform (and advertises colour management to clients); 10-bit
          # scanout keeps the P3 transform from banding.
          postInstall = old.postInstall + ''
            wrapProgram $out/bin/river \
              --set-default WLR_RENDERER vulkan \
              --set-default RIVER_RENDER_BIT_DEPTH 10 \
              --set-default XDG_CURRENT_DESKTOP river
          '';
        });
        extraPackages = [ ];
      };

      # libadwaita apps read light/dark from the portal Settings backend, and
      # river has no gnome-settings-daemon to answer it (see gtk.nix).
      xdg.portal.config.river."org.freedesktop.impl.portal.Settings" = "gtk";
    };
}
