{ pkgs, lib, username, ... }:

{
  imports = [
    ./modules/home/shell/zsh.nix
    ./modules/home/shell/git.nix
    ./modules/home/editor/helix.nix
    ./modules/home/terminal/ghostty.nix
    ./modules/home/multiplexer/zellij.nix
    ./modules/home/filemanager/yazi.nix
    ./modules/home/packages.nix # Platform-aware package list
  ] ++ lib.optional pkgs.stdenv.isLinux ./modules/home/desktop/niri.nix;

  home.username = username;
  home.homeDirectory = if pkgs.stdenv.isDarwin then "/Users/${username}" else "/home/${username}";
  home.stateVersion = "25.11";

  # Global Font Config
  fonts.fontconfig.enable = true;
  programs.home-manager.enable = true;
}
