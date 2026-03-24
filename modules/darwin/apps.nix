{ pkgs, ... }:
{
  homebrew = {
    enable = true;

    # Updates homebrew packages on activation,
    # can make darwin-rebuild slower but keeps things up to date.
    onActivation.autoUpdate = true;

    # 'zap' removes manually installed brews and casks that aren't in this file.
    onActivation.cleanup = "zap";

    casks = [
      "helium-browser"
      "obs"
    ];

    # You can also install standard brew formulas here if they aren't in nixpkgs
    brews = [
      # "mas"
    ];
  };
}
