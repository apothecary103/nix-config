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
          #
          # Honeykrisp's lossless compression breaks that 10-bit path: every
          # new frame flickers a border round the panel, while 8-bit, GLES at
          # 10 bits and 10 bits without compression are all clean. So river
          # itself renders uncompressed; river/init clears it for the rest.
          postInstall = old.postInstall + ''
            wrapProgram $out/bin/river \
              --set-default WLR_RENDERER vulkan \
              --set-default RIVER_RENDER_BIT_DEPTH 10 \
              --set-default ASAHI_MESA_DEBUG nocompress \
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
