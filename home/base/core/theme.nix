{
  inputs,
  pkgs,
  ...
}: {
  imports = [
    inputs.catppuccin.homeModules.catppuccin
  ];

  catppuccin = {
    enable = true;
    autoEnable = true;
    flavor =
      if pkgs.stdenv.isDarwin
      then "macchiato"
      else "mocha";
    accent = "blue";

    helix.enable = false;
    nushell.enable = false;
  };
}
