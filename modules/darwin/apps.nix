{
  config,
  inputs,
  username,
  ...
}:
{
  imports = [
    inputs.nix-homebrew.darwinModules.nix-homebrew
  ];

  nix-homebrew = {
    enable = true;
    enableRosetta = true;
    user = username;

    taps = {
      "homebrew/homebrew-core" = inputs.homebrew-core;
      "homebrew/homebrew-cask" = inputs.homebrew-cask;
    };

    mutableTaps = false;
  };

  homebrew = {
    enable = true;
    onActivation.autoUpdate = true;
    onActivation.cleanup = "zap";

    taps = builtins.attrNames config.nix-homebrew.taps;

    casks = [
      # "helium-browser"
      "obs"
      # "blender"
      "linearmouse"
      # "foobar2000"
      "background-music"
    ];

    brews = [
      # "mas"
    ];
  };
}
