{
  pkgs,
  username,
  inputs,
  ...
}:

{
  home-manager.users.${username} = {
    home.packages = with pkgs; [
      awww
      brightnessctl
      wf-recorder
      tuigreet
      grim
      slurp
      fuzzel
      waybar
      hyprsunset
      wl-clipboard
      whitesur-cursors
      mako
      swayosd
      hyprland
      rofi
      wayfreeze
      hyprshot
      eww
      vips
      inputs.helium.packages.${system}.default
      firefox
    ];
  };
}
