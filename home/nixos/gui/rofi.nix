{ config, pkgs, theme, ... }:

let
  inherit (config.lib.formats.rasi) mkLiteral;
  c = theme.colors;

  rofi-wallpaper = pkgs.writeShellApplication {
    name = "rofi-wallpaper";
    runtimeInputs = with pkgs; [ rofi imagemagick libnotify ]; 
    text = builtins.readFile ../scripts/rofi-wallpaper.sh;
  };

in
{
  home.packages = [ rofi-wallpaper ];

  programs.rofi = {
    enable = true;
    
    extraConfig = {
      modi = "drun";
      font = "MapleMono NF CN Medium 12";
      display-drun = "drun";
      drun-display-format = "{name}";
      show-icons = true;
      icon-theme = "pixora";
    };

    theme = {
      "*" = {
        bg = mkLiteral c.base;
        fg = mkLiteral c.text;
        prompt-fg = mkLiteral c.subtext1;
        placeholder-fg = mkLiteral c.surface2;
        selected-bg = mkLiteral c.text;
        selected-fg = mkLiteral c.base;

        background-color = mkLiteral "transparent";
        text-color = mkLiteral "@fg";
        margin = 0;
        padding = 0;
        spacing = 0;
      };

      window = {
        width = mkLiteral "480px";
        background-color = mkLiteral "@bg";
        padding = mkLiteral "25px";
        border = mkLiteral "0px";
      };

      mainbox = {
        spacing = mkLiteral "10px";
        children = mkLiteral "[ inputbar, listview ]";
      };

      inputbar = {
        spacing = mkLiteral "10px";
        children = mkLiteral "[ prompt, entry ]";
        padding = mkLiteral "0px 12px 15px 12px";
      };

      prompt = {
        text-color = mkLiteral "@prompt-fg";
      };

      entry = {
        placeholder = "search...";
        placeholder-color = mkLiteral "@placeholder-fg";
        text-color = mkLiteral "@fg";
        cursor = mkLiteral "text";
      };

      listview = {
        lines = 6;
        spacing = mkLiteral "5px";
        scrollbar = false;
        border = mkLiteral "0px";
      };

      element = {
        padding = mkLiteral "10px 12px";
        background-color = mkLiteral "transparent";
        text-color = mkLiteral "@fg";
        spacing = mkLiteral "10px";
      };

      "element normal.normal, element alternate.normal" = {
        background-color = mkLiteral "transparent";
        text-color = mkLiteral "@fg";
      };

      element-icon = {
        background-color = mkLiteral "transparent";
        size = mkLiteral "18px";
        cursor = mkLiteral "inherit";
      };

      element-text = {
        background-color = mkLiteral "inherit";
        text-color = mkLiteral "inherit";
        vertical-align = mkLiteral "0.5";
      };

      "element selected.normal" = {
        background-color = mkLiteral "@selected-bg";
        text-color = mkLiteral "@selected-fg";
      };
    };
  };
}
