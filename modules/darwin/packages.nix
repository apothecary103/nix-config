{inputs, ...}: {
  flake.modules.darwin.base.nixpkgs.overlays = [
    inputs.emacs-overlay.overlays.default
    (final: _prev: {
      teamspeak6-client = final.callPackage ../../pkgs/teamspeak6-client/package.nix {};
    })
  ];

  flake.modules.homeManager.darwin = {pkgs, ...}: {
    home.packages = with pkgs; [
      # CLI Tools
      llama-cpp
      qemu

      # GUI Applications
      yabai
      skhd
      sketchybar
      aseprite
      emacs-unstable
      teamspeak6-client
      # steam
      # moonlight-qt
    ];
  };
}
