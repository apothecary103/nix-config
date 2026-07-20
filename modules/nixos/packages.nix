{ pkgs, username, inputs, ... }:

let
  stable-pkgs = import inputs.nixpkgs-stable {
    system = pkgs.system;
    # config.allowUnfree = true;
  };
in {
  home-manager.users.${username} = {
    home.packages = with pkgs; [
      fuzzel
      waybar
      inputs.awww.packages.${pkgs.stdenv.hostPlatform.system}.awww
      brightnessctl
      wf-recorder
      tuigreet

      # Apps
      keypunch
      video-trimmer
      stable-pkgs.blender
      librewolf
    ];
  };
}
