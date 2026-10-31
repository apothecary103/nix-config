{
  # The compositor is river with ./patches/river applied in order, then wrapped
  # with the settings those patches read. nixpkgs' river module still means
  # river-classic, but takes the new river as its package: it brings the
  # session file, portals and the rest of a wayland session.
  flake.modules.nixos.base =
    { lib, pkgs, ... }:
    let
      wlroots = pkgs.wlroots_0_20.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ lib.filesystem.listFilesRecursive ./patches/wlroots;
      });
    in
    {
      programs.river-classic = {
        enable = true;
        # wlroots with backdrop blur (patches/wlroots), which river's layer
        # surfaces ask for by namespace (patches/river/0003-blur.patch).
        package = (pkgs.river.override { wlroots_0_20 = wlroots; }).overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ lib.filesystem.listFilesRecursive ./patches/river;
          nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.makeWrapper ];
          # Vulkan is the only wlroots renderer that applies an output colour
          # transform (and advertises colour management to clients); 10-bit
          # scanout keeps the P3 transform from banding (on Asahi it needs
          # hosts/frieren/graphics.nix, or every new frame flickers the edges).
          postInstall = old.postInstall + ''
            wrapProgram $out/bin/river \
              --set-default WLR_RENDERER vulkan \
              --set-default RIVER_RENDER_BIT_DEPTH 10 \
              --set-default RIVER_BLUR "bar:2,launcher:4,popover:4,osd:4" \
              --set-default XDG_CURRENT_DESKTOP river
            # Its log goes to the journal as `river`, where nothing else keeps it.
            substituteInPlace $out/share/wayland-sessions/river.desktop \
              --replace-fail "Exec=river" "Exec=systemd-cat -t river river"
          '';
        });
        extraPackages = [ ];
      };

      # A way in when Vulkan does not come up: the same river on GLES, without
      # the P3 transform, as its own entry in the greeter.
      services.displayManager.sessionPackages = [
        (
          (pkgs.writeTextDir "share/wayland-sessions/river-gles.desktop" ''
            [Desktop Entry]
            Name=River (GLES)
            Comment=river on the GLES renderer, without the Display P3 transform
            Exec=systemd-cat -t river env WLR_RENDERER=gles2 river
            Type=Application
          '').overrideAttrs
            { passthru.providedSessions = [ "river-gles" ]; }
        )
      ];

      # libadwaita apps read light/dark from the portal Settings backend, and
      # river has no gnome-settings-daemon to answer it (see gtk.nix).
      xdg.portal.config.river."org.freedesktop.impl.portal.Settings" = "gtk";
    };
}
