{
  pkgs,
  username,
  ...
}:

{
  home-manager.users.${username} = {
    home.packages = with pkgs; [
      awww
      brightnessctl
      wf-recorder
      tuigreet

      # Wayland
      grim
      slurp
      fuzzel
      waybar
      wezterm
      hyprsunset
      wl-clipboard
      whitesur-cursors
      mako
      swayosd
      papirus-icon-theme

      # Apps
      ungoogled-chromium
    ];
  };
}
