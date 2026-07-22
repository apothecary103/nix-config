# ❄️ nix-config

My nix flake for my MacBook dual-booting NixOS and macOS (nix-darwin).

![rice](./assets/rice.avif)
*Frieren — NixOS*

## Hosts

- **frieren** — NixOS on Apple Silicon (via `nixos-apple-silicon`), Wayland desktop.
- **fern** — macOS, managed with nix-darwin + home-manager.

## Structure

This flake follows the [dendritic pattern](https://github.com/vic/import-tree):
`flake.nix` just points `flake-parts` at `import-tree ./modules`, and every
`.nix` file under `modules/` is its own self-contained flake-parts module,
auto-discovered and imported — no manual import lists to maintain.

A feature file typically declares itself once per relevant class and lets
hosts compose from there:

- `flake.modules.nixos.base` / `flake.modules.darwin.base` — shared NixOS /
  darwin system config.
- `flake.modules.homeManager.{base,linux,darwin}` — shared, Linux-only, and
  darwin-only user environment.
- `flake.modules.nixos."hosts/frieren"` / `flake.modules.darwin."hosts/fern"`
  — the actual host definitions, which import the classes above and layer on
  host-specific bits (hardware, networking, etc).

`modules/flake/` holds flake-parts wiring (systems, formatter, shared
`_module.args`); `modules/desktop/`, `modules/programs/`, `modules/system/`
hold the actual feature modules, grouped by concern rather than by host.

## Desktop

Linux (frieren) boots to greetd + tuigreet, with a choice of Hyprland or Niri
as the compositor. waybar, rofi, mako, and swayosd round out the session.
macOS (fern) runs yabai (built from a fork with the scripting addition) +
skhd for tiling and keybinds, with sketchybar available alongside it.

Shared across both: Ghostty as the terminal, Fish as the shell, Helix/Neovim
for editing, Yazi for files, tmux, LibreWolf, MPD + rmpc for music, pass for
secrets, Catppuccin theming, and Maple Mono NF CN / Adwaita Sans for
typography.

## Branches

- `main` — the daily driver, always meant to build and boot cleanly on both
  hosts.
- `experimental` — where new stuff gets tried before it's trusted on `main`.
  Right now that's **finix**: replacing systemd on `frieren` with finit (PID 1)
  + dinit (per-user services) + eudev + elogind, so the compositor can crash
  and restart without taking audio or mpd down with it. See `docs/finix.md`
  on that branch for the full writeup.

## Deploy

Rebuilds go through [`nh`](https://github.com/nix-community/nh), which is
already pointed at this flake and handles cleanup too:

```bash
# NixOS (frieren)
nh os switch

# macOS (fern)
nh darwin switch
```
