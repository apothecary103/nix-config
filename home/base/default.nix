{ pkgs, username, ... }:

{
  imports = [
    ./core
    ./tui
    ./gui
  ];

  home.username = username;
  home.homeDirectory = if pkgs.stdenv.isDarwin then "/Users/${username}" else "/home/${username}";

  home.stateVersion = "26.05"; 
  programs.home-manager.enable = true;
}
