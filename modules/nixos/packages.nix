{ pkgs, username, inputs, ... }:

{
  home-manager.users.${username} = {
    home.packages = with pkgs; [
      niri
      fuzzel
      tuigreet
      librewolf
      brightnessctl
      inputs.awww.packages.${pkgs.stdenv.hostPlatform.system}.awww
    ];
  };
}
