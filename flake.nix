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
    apple-silicon.url = "github:nix-community/nixos-apple-silicon";
    # Asahi Linux finished to behave like this MacBook's macOS: its patches,
    # the Mac's own numbers and the modules that apply them. A flake of its
    # own in ./silicon-bakery, so it can be imported elsewhere or split out.
    silicon-bakery = {
      url = "path:./silicon-bakery";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.apple-silicon.follows = "apple-silicon";
    };
    asahi-firmware = {
      url = "git+ssh://git@codeberg.org/frieren/asahi-firmware?ref=main";
      flake = false;
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    yabai-src = {
      url = "github:agg23/yabai/macos-27";
      flake = false;
    };
    helium = {
      url = "github:amaanq/helium-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    orchard = {
      url = "github:apothecary103/nix-orchard";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.hjem.follows = "hjem";
      inputs.hjem-rum.follows = "hjem-rum";
    };
    steelix = {
      url = "github:mattwparas/helix/steel-event-system";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nvf = {
      url = "github:NotAShelf/nvf";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zmk-nix = {
      url = "github:lilyinstarlight/zmk-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Not following nixpkgs: the packages are built against its own pin, which
    # is what cache.numtide.com holds.
    llm-agents.url = "github:numtide/llm-agents.nix";
  };

  # Dendritic pattern: every file under modules/ is a flake-parts module,
  # auto-imported by import-tree. Features contribute to
  # flake.modules.{nixos,darwin,hjem}.* and hosts compose them.
  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);
}
