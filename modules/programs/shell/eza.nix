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

      # Fish only: in nushell `ls` returns a table the rest of the pipeline can
      # act on, which aliasing it to eza would throw away.
      #
      # The colours come from ~/.config/eza/theme.yml, written by the active
      # port (desktop/theme.nix).
      rum.programs.fish.aliases = aliases;
    };
}
