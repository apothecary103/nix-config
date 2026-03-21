{ pkgs, lib, username, ... }:

{
  imports =
    [ ./base ]
    ++ lib.optionals pkgs.stdenv.isDarwin [ ./darwin ]
    ++ lib.optionals pkgs.stdenv.isLinux [ ./nixos ];

  home.username = username;
  home.homeDirectory = if pkgs.stdenv.isDarwin then "/Users/${username}" else "/home/${username}";
  home.stateVersion = "25.11";

  programs.home-manager.enable = true;
}
