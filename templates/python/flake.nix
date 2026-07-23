{
  description = "Python development environment";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      devShells = forAllSystems (pkgs: {
        # Interpreter comes from nix; project dependencies are managed by uv
        # (`uv venv` then `uv add …`), which keeps them in a local .venv rather
        # than the global profile. ruff = lint/format, ty = type checking.
        default = pkgs.mkShell {
          packages = with pkgs; [
            python3
            uv
            ruff
            ty
          ];
        };
      });
    };
}
