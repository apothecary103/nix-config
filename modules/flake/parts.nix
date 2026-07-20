{ inputs, ... }: {
  # Provides the flake.modules.<class>.<name> option tree.
  imports = [ inputs.flake-parts.flakeModules.modules ];

  systems = [
    "aarch64-darwin"
    "x86_64-darwin"
    "aarch64-linux"
    "x86_64-linux"
  ];

  perSystem = { pkgs, ... }: {
    # nixfmt-tree = treefmt wrapping nixfmt, so `nix fmt` recurses the repo.
    formatter = pkgs.nixfmt-tree;
  };
}
