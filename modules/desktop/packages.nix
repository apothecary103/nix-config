{
  flake.modules.homeManager.linux = { pkgs, ... }: {
    home.packages = with pkgs; [
      awww
      brightnessctl
      wf-recorder
      tuigreet
      grim
      slurp
      fuzzel
      hyprsunset
      wl-clipboard
      whitesur-cursors
      mako
      swayosd
      wayfreeze
      eww
      vips
    ];
  };
}
