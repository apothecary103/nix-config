{
  description = "Web (TypeScript/Tailwind) development environment";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            nodejs
            pnpm
            typescript
            typescript-language-server
            tailwindcss-language-server
            # provides vscode-css-language-server + vscode-html-language-server
            vscode-langservers-extracted
          ];
        };
      });
    };
}
