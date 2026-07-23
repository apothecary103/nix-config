{
  flake.templates = {
    rust = {
      path = ../../templates/rust;
      description = "Rust devShell (fenix toolchain, rust-analyzer) + direnv + helix LSP";
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
