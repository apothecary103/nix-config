{
  # Qt drawn with its own Fusion style in the system palette, through qt5ct
  # and qt6ct, so Qt5 and Qt6 apps match GTK and follow the orchard theme.
  # Fusion ships with qtbase, so no style plugin has to track Qt releases.
  flake.modules.nixos.base = {
    qt = {
      enable = true;
      platformTheme = "qt5ct";
    };
  };

  flake.modules.hjem.linux =
    {
      lib,
      pkgs,
      palette,
      ...
    }:
    let
      argb = hex: "#ff${lib.removePrefix "#" hex}";
      roles =
        colours:
        lib.concatMapStringsSep ", " argb [
          colours.windowText
          colours.button
          colours.light
          colours.midlight
          colours.dark
          colours.mid
          colours.text
          colours.brightText
          colours.buttonText
          colours.base
          colours.window
          colours.shadow
          colours.highlight
          colours.highlightedText
          colours.link
          colours.linkVisited
          colours.alternateBase
          colours.base # NoRole
          colours.toolTipBase
          colours.toolTipText
          colours.placeholderText
          colours.highlight # Accent
        ];

      s = palette.surface;

      # Windows and buttons on the panel colour, fields on the background,
      # as Adwaita lays them out; selections in the theme's deep blue, which
      # keeps light text readable where the rose accent would not.
      active = {
        windowText = s.text;
        button = s.panel;
        light = s.background;
        midlight = s.neutral0;
        dark = s.neutral2;
        mid = s.neutral1;
        text = s.text;
        brightText = palette.status.error;
        buttonText = s.text;
        base = s.background;
        window = s.panel;
        shadow = s.neutral4;
        highlight = palette.hue.snow;
        highlightedText = s.background;
        link = palette.hue.snow;
        linkVisited = palette.hue.purple;
        alternateBase = s.neutral0;
        toolTipBase = s.background;
        toolTipText = s.text;
        placeholderText = s.neutral4;
      };

      disabled = active // {
        windowText = s.neutral4;
        text = s.neutral4;
        buttonText = s.neutral4;
        highlight = s.neutral1;
        highlightedText = s.textDim;
        placeholderText = s.neutral2;
      };

      scheme = pkgs.writeText "qt-colours.conf" ''
        [ColorScheme]
        active_colors=${roles active}
        inactive_colors=${roles active}
        disabled_colors=${roles disabled}
      '';

      # The same fonts as GTK (see gtk.nix). QFont strings must be quoted, or
      # QSettings splits them on the commas.
      conf = fonts: ''
        [Appearance]
        style=Fusion
        custom_palette=true
        color_scheme_path=${scheme}
        icon_theme=Adwaita
        standard_dialogs=xdgdesktopportal

        [Fonts]
        ${fonts}
      '';
    in
    {
      xdg.config.files = {
        "qt6ct/qt6ct.conf".text = conf ''
          general="Adwaita Sans,9.75,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
          fixed="Maple Mono NF CN,11,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
        '';
        "qt5ct/qt5ct.conf".text = conf ''
          general="Adwaita Sans,9.75,-1,5,50,0,0,0,0,0"
          fixed="Maple Mono NF CN,11,-1,5,50,0,0,0,0,0"
        '';
      };
    };
}
