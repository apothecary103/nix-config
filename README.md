❄️ My Nix flake for my MacBook dual-booting NixOS and macOS (nix-darwin).

![rice](./assets/rice.avif)
*Frieren — NixOS*

| Host     | OS              |
| -------- | --------------- |
| Frieren  | NixOS           |
| Fern     | macOS / darwin  |

## Components

|                    | NixOS |
| -----------------  | ------- |
| Wayland Compositor | Hyprland |
| Display Manager    | greetd + tuigreet |
| Terminal Emulator  | Ghostty |
| Shell              | Fish |
| Status Bar         | waybar |
| Launcher           | rofi |
| Notifications      | mako |
| Editor             | Helix, Neovim (via nvf) |
| File Manager       | Yazi |
| Multiplexer        | Zellij |
| Web Browser        | LibreWolf |
| Music              | MPD + mpdris2 + rmpc |
| Secrets            | pass (password-store) |
| Colour Scheme      | Catppuccin Mocha |
| Font               | Maple Mono NF CN |

## Custom Packages

- **yaagl** — Anime game launchers (Genshin Impact, HSR, ZZZ), aarch64-darwin + x86_64-darwin
- **teamspeak6-client** — TeamSpeak 6 Beta, aarch64-darwin

## Deploy

```bash
# NixOS
sudo nixos-rebuild switch --flake .#frieren

# macOS
darwin-rebuild switch --flake .#fern

# Or with the NH helper
nh os switch .
```
