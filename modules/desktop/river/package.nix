{
  # The compositor is Silicon Bakery's river (the panel's colour, HDR, blur by
  # namespace, on its wlroots and libinput; see silicon-bakery/pkgs), wrapped
  # with the settings those patches read. nixpkgs' river module still means
  # river-classic, but takes the new river as its package: it brings the
  # session file, portals and the rest of a wayland session.
  flake.modules.nixos.base =
    { lib, pkgs, ... }:
    {
      programs.river-classic = {
        enable = true;
        package = pkgs.siliconBakery.river.overrideAttrs (old: {
          nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.makeWrapper ];
          # Vulkan is the only wlroots renderer that applies an output colour
          # transform (and advertises colour management to clients); 10-bit
          # scanout keeps the P3 transform from banding (on Asahi it needs
          # Silicon Bakery's Mesa patch, or every new frame flickers the edges).
          postInstall = old.postInstall + ''
            wrapProgram $out/bin/river \
              --set-default WLR_RENDERER vulkan \
              --set-default RIVER_RENDER_BIT_DEPTH 10 \
              --set-default RIVER_BLUR "bar:5,launcher:3,popover:3,osd:3" \
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

      # Screen sharing (xdg-desktop-portal-wlr): it asks which screen through a
      # menu, here fuzzel styled as the launcher, where its default is a slurp
      # crosshair that gives up silently, as "no output found", on Escape or a
      # stray click. The service reads only this file (--config), never
      # ~/.config. Sixty frames a second is enough for any call and spares
      # half the copying at 120 Hz.
      xdg.portal.wlr.settings.screencast = {
        chooser_type = "dmenu";
        chooser_cmd = "${lib.getExe pkgs.fuzzel} --dmenu --prompt 'share  ' --lines 6";
        max_fps = 60;
      };
    };
}
