# Project starters: `nix flake init -t ~/nix-config#<name>` scaffolds a flake +
# .envrc + .helix/languages.toml so the toolchain is direnv-scoped, not global.
{
  flake.templates = {
    rust = {
      path = ../../templates/rust;
      description = "Rust devShell (cargo, rust-analyzer, clippy, rustfmt) + direnv + helix LSP";
    };
    python = {
      path = ../../templates/python;
      description = "Python devShell (uv, ruff, ty) + direnv + helix LSP";
    };
    web = {
      path = ../../templates/web;
      description = "Web devShell (node, pnpm, ts/tailwind/css/html LSPs) + direnv + helix LSP";
    };
  };
}
