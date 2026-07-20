{ inputs, ... }: {
  flake.modules.darwin.base.nixpkgs.overlays = [
    inputs.emacs-overlay.overlays.default
  ];

  flake.modules.homeManager.darwin = { pkgs, ... }: {
    home.packages = [ pkgs.emacs-unstable ];
  };
}
