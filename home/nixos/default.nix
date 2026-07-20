{ pkgs, lib, ... }:
{
  config = lib.mkIf pkgs.stdenv.isLinux {
    imports = [
      ./gui
      ./core
    ];
  };
}
