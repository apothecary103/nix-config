{ pkgs, username, inputs, ... }:

{
  home-manager.users.${username} = {
    home.packages = with pkgs; [
      niri
      hyprland
      grim
      slurp
      fuzzel
      tuigreet
      librewolf
      brightnessctl
      waybar
      inputs.awww.packages.${pkgs.stdenv.hostPlatform.system}.awww
    ];
  };
}
