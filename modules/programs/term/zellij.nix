{ inputs, ... }:

{
  # nixpkgs lags upstream (0.44.3 against 0.45.0), so zellij comes from
  # a-kenji/zellij-nix, which tracks the git tree.
  flake.modules.hjem.base =
    {
      lib,
      pkgs,
      theme,
      ...
    }:

    {
      # zellij-nix omits zlib and curl, so on darwin libz-sys falls back to a
      # vendored zlib whose headers are missing, and the final link fails on
      # -lcurl.
      # zellij-upstream keeps the plugin wasm shipped in the release tree; the
      # default package recompiles it, and that build panics in wasmi's
      # translator ("cmp+branch fusion must succeed") while loading a plugin.
      packages = [
        (inputs.zellij.packages.${pkgs.stdenv.hostPlatform.system}.zellij-upstream.overrideAttrs (old: {
          nativeBuildInputs = old.nativeBuildInputs ++ [ (lib.getDev pkgs.curl) ];
          buildInputs = old.buildInputs ++ [
            pkgs.zlib
            pkgs.curl
          ];
        }))
      ];

      # No shell integration: it auto-starts a session from every interactive
      # shell.
      xdg.config.files."zellij/config.kdl".text = ''
        default_layout "compact"
        theme "${theme.zellij.themeName}"
      '';
    };
}
