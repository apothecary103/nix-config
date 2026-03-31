{ pkgs, username, inputs, ... }:

let
  stable-pkgs = import inputs.nixpkgs-stable {
    system = pkgs.system;
    # config.allowUnfree = true;
  };
in {
  home-manager.users.${username} = {
    home.packages = with pkgs; [
      niri
      grim
      stable-pkgs.blender
      video-trimmer
      wf-recorder
      slurp
      fuzzel
      tuigreet
      librewolf
      brightnessctl
      waybar
      hyprland
      # inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland
      inputs.awww.packages.${pkgs.stdenv.hostPlatform.system}.awww
    ];
  };
}
