{
  flake.modules.hjem.base =
    { lib, pkgs, ... }:
    let
      eza = "${lib.getExe pkgs.eza} --git --icons=auto";

      aliases = {
        ls = eza;
        ll = "${eza} -l";
        la = "${eza} -a";
        lla = "${eza} -la";
        lt = "${eza} --tree";
      };
    in
    {
      packages = [ pkgs.eza ];

      # The colours come from ~/.config/eza/theme.yml, written by the active
      # port (desktop/theme.nix).
      rum.programs = {
        fish.aliases = aliases;
        nushell.aliases = aliases;
        zsh.initConfig = lib.concatLines (
          lib.mapAttrsToList (name: value: "alias ${name}=${lib.escapeShellArg value}") aliases
        );
      };
    };
}
