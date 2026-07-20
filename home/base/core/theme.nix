{ inputs, ... }:

{
  imports = [
    inputs.catppuccin.homeModules.catppuccin
  ];

  catppuccin = {
    enable = true;
    autoEnable = true; 
    flavor = "mocha";
    # flavor = "macchiato";
    accent = "blue";

    helix.enable = false;
    nushell.enable = false;
  };
}
