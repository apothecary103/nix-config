{ pkgs, username, ... }:

let
  daedra = pkgs.rustPlatform.buildRustPackage rec {
    pname = "daedra";
    version = "0.3.2";
    src = pkgs.fetchCrate {
      inherit pname version;
      hash = "sha256-Z5iDJKVZRtrlvS4BcP6c6khsGL8JL6+C1jmrRGkVlBk=";
    };
    cargoHash = "sha256-kbUgvAmgcSRgtIczn32xWcq75YUg4YGvUOyYUOdAKYQ=";
    doCheck = false;
    meta.mainProgram = "daedra";
  };
in
{
  home-manager.users.${username} = {
    home.packages =
      (with pkgs; [
        # CLI Tools
        rustup

        # GUI Applications
        yabai
        skhd
        jankyborders
        sketchybar
        llama-cpp
        opencode
        # emacs-unstable
      ])
      ++ [ daedra ];
  };
}
