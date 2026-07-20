{ inputs, ... }: {
  flake.modules.darwin.base = {
    imports = [ inputs.nix-index-database.darwinModules.default ];
    programs.nix-index-database.comma.enable = true;
  };

  flake.modules.nixos.base = {
    imports = [ inputs.nix-index-database.nixosModules.default ];
    programs.nix-index-database.comma.enable = true;
  };
}
