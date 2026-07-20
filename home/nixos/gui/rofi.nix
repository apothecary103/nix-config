{ config, pkgs, ... }:

let
  inherit (config.lib.formats.rasi) mkLiteral;

  # 1. Define the wallpaper picker script
  rofi-wallpaper = pkgs.writeShellScriptBin "rofi-wallpaper" ''
    #!/usr/bin/env bash

    WALL_DIR="$HOME/Pictures/Wallpapers"

    if [ ! -d "$WALL_DIR" ]; then
      notify-send "Rofi Wallpaper" "Directory $WALL_DIR not found."
      exit 1
    fi

    # 2. Find images, extract filename, and append the path as an icon property for rofi
    selected=$(find "$WALL_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) | while read -r img; do
      # The \0icon\x1f syntax tells rofi to load the image as a thumbnail
      echo -en "$(basename "$img")\0icon\x1f$img\n"
    done | rofi -dmenu \
      -show-icons \
      -p "wallpaper " \
      -theme-str 'window { width: 750px; }' \
      -theme-str 'listview { columns: 3; lines: 2; flow: horizontal; scrollbar: false; fixed-columns: true; }' \
      -theme-str 'element { orientation: vertical; padding: 15px; }' \
      -theme-str 'element-icon { size: 180px; }' \
      -theme-str 'element-text { horizontal-align: 0.5; }'
    )

    # 3. If an image was selected, apply it with awww
    if [ -n "$selected" ]; then
      # Ensure the daemon is running (adjust to awww-daemon if the binary name differs)
      awww query || awww daemon &
      sleep 0.1 
      
      # Set the wallpaper
      awww img "$WALL_DIR/$selected" \
        --transition-type grow \
        --transition-pos 0.5,0.5 \
        --transition-step 90
    fi
  '';

in
{
  # Make the script available in your environment
  home.packages = [ rofi-wallpaper ];

  programs.rofi = {
    enable = true;
    
    extraConfig = {
      modi = "drun";
      font = "MapleMono NF CN Medium 12";
      display-drun = "drun";
      drun-display-format = "{name}";
      # Ensure icons are globally allowed so our overrides work
      show-icons = true;
      icon-theme = "pixora";
    };

    theme = {
      "*" = {
        bg = mkLiteral "#24273a";
        fg = mkLiteral "#cad3f5";
        prompt-fg = mkLiteral "#b8c0e0";
        placeholder-fg = mkLiteral "#5b6078";
        selected-bg = mkLiteral "#cad3f5";
        selected-fg = mkLiteral "#24273a";

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
        # Optional: Add a subtle border radius if you like
        # border-radius = mkLiteral "12px"; 
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
        # Optional: Round the corners of the selected item
        # border-radius = mkLiteral "8px";
      };
    };
  };
}
