{ pkgs, username, inputs, ... }:

{
  home-manager.users.${username} = {
    home.packages = with pkgs; [
      niri
      hyprland
      uwsm
      grim
      slurp
      fuzzel
      tuigreet
      librewolf
      brightnessctl
      waybar
      inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland
      inputs.awww.packages.${pkgs.stdenv.hostPlatform.system}.awww
    ];
  };
}
