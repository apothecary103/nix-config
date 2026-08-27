{
  inputs,
  username,
  ...
}:
{
  flake.modules.darwin.base = { config, ... }: {
    imports = [ inputs.nix-homebrew.darwinModules.nix-homebrew ];

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
      # mutableTaps = false makes the taps read-only store paths, so `brew
      # update` can only fail on them.
      onActivation.autoUpdate = false;
      onActivation.cleanup = "zap";

      taps = builtins.attrNames config.nix-homebrew.taps;

      casks = [
        "obs"
        "linearmouse"
        "playcover-community"
        "teamspeak-client@beta"
        "steam"
        "finetune"
        "blackhole-2ch"
        "claude"
      ];
    };
  };
}
