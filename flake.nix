{
  description = "My Nix Configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    import-tree.url = "github:vic/import-tree";
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hjem = {
      url = "github:feel-co/hjem";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hjem-rum = {
      url = "github:snugnug/hjem-rum";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.hjem.follows = "hjem";
    };
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };
    apple-silicon.url = "github:tpwrules/nixos-apple-silicon";
    asahi-firmware = {
      url = "git+ssh://git@codeberg.org/frieren/asahi-firmware?ref=main";
      flake = false;
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    preservation.url = "github:nix-community/preservation";
    niri = {
      url = "github:epireyn/niri-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    yabai-src = {
      url = "github:agg23/yabai/macos-27";
      flake = false;
    };
    zellij.url = "github:a-kenji/zellij-nix";
    # Not published yet, so this is the working copy in ~/Projects; swap for
    # github: once it is pushed.
    orchard = {
      url = "git+file:///Users/apothecary/Projects/nix-orchard";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-wrapper-modules = {
      url = "github:BirdeeHub/nix-wrapper-modules";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    luna-nvim = {
      url = "github:wtfox/luna.nvim";
      flake = false;
    };
    bg-nvim = {
      url = "github:typicode/bg.nvim";
      flake = false;
    };
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zmk-nix = {
      url = "github:lilyinstarlight/zmk-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # Dendritic pattern: every file under modules/ is a flake-parts module,
  # auto-imported by import-tree. Features contribute to
  # flake.modules.{nixos,darwin,hjem}.* and hosts compose them.
  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);
}
