<h2 align="center">❄️ Apothecary's Nix Config </h2>
<p align="center">
  <img src="https://raw.githubusercontent.com/catppuccin/catppuccin/main/assets/palette/macchiato.png" width="400" />
</p>
<p align="center">
  <img src="https://img.shields.io/badge/NixOS-unstable-informational.svg?style=for-the-badge&logo=nixos&color=a2bfff&logoColor=D9E0EE&labelColor=302D41">
  <img src="https://img.shields.io/endpoint?url=https%3A%2F%2Fghloc.vercel.app%2Fapi%2Fapothecary103%2Fnix-config%2Fbadge&style=for-the-badge&color=eed49f&labelColor=302D41&logoColor=D9E0EE&logo=pipecat&label=Lines%20of%20Code">
  <img src="https://img.shields.io/badge/Pattern-Dendritic-informational.svg?style=for-the-badge&color=a6da95&labelColor=302D41&logo=mongodb&logoColor=D9E0EE">
</p>
<p align="center">
  This repository serves as the home to my Nix flake that declaratively configures my Apple Silicon MacBook running NixOS (frieren) and nix-darwin (fern).
</p>

![Frieren — NixOS](./assets/rice.avif)

## The Setup

- **frieren** (NixOS): niri, quickshell, greetd + tuigreet
- **fern** (nix-darwin): yabai + skhd

**Shared Stack:**
- **Terminal & Shell:** Ghostty, Fish, Nushell
- **Editor:** Helix, Neovim
- **Apps:** LibreWolf, Yazi (files), MPD + rmpc (music), pass (secrets)
- **Aesthetics:** Catppuccin, Maple Mono NF CN, Adwaita Sans

## Structure

Built on `flake-parts` using the dendritic pattern (`import-tree`). No giant manual import lists.

Drop a `.nix` file in `modules/desktop/`, `modules/programs/`, or `modules/system/`, and it's auto-discovered. Features declare themselves once, and hosts (`hosts/frieren` or `hosts/fern`) pull in what they need via shared base classes. Hjem and hjem-rum manage the user environment directly from the NixOS and nix-darwin rebuilds; Home Manager is not used.

## Daily Driving

Rebuilds and garbage collection are handled by `nh`:

```bash
# NixOS
nh os switch

# macOS
nh darwin switch

# Build and flash both halves of the ZMK keyboard (Linux or macOS)
nix build .#zmk
nix run .#zmk-flash
```

## Fresh Install (NixOS / Asahi)

`frieren` runs on LUKS-encrypted btrfs. Firmware comes from a private flake input (`asahi-firmware`), and agenix decrypts with the same `~/.ssh/id_ed25519` that fetches it, so keep that key (the `frieren` entry in `secrets.nix`) on the installer USB.

> [!TIP]
> ^. .^₎Ⳋ&nbsp;&nbsp;Before you begin: make sure you have a reliable external backup of your macOS data. While resizing APFS containers is generally safe, low-level partitioning always carries minor risks.

1. **From macOS:** run our wrapper around the Asahi installer. It offers a single **NixOS (frieren)** option: the Asahi UEFI environment plus an empty root partition.
   ```bash
   curl -L https://raw.githubusercontent.com/apothecary103/nix-config/main/modules/hosts/frieren/asahi.sh | sh
   ```
   Follow its prompts to resize macOS and bless the bootloader in recoveryOS.

2. **From the `nixos-apple-silicon` installer USB:** connect to Wi-Fi (`iwctl station wlan0 connect <SSID>`), then:
   ```bash
   sudo nix --extra-experimental-features 'nix-command flakes' \
     run github:apothecary103/nix-config#frieren-install -- /path/to/frieren-id_ed25519
   ```
   This finds the new root partition, encrypts it with the LUKS UUID from `disko.nix`, creates the btrfs subvolumes, installs NixOS, places the key and a checkout of this repo in your home, and asks for your password. Then reboot.

When nixos-apple-silicon release notes request new device firmware, run the stock `curl https://alx.sh | sh` and choose **Rebuild vendor firmware package**. Copy the resulting `vendorfw/firmware.cpio` into the private `asahi-firmware` input and update its lock before rebuilding NixOS. This is currently required for ambient-light sensor calibration.
