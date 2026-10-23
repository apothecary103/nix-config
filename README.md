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

- **frieren** (NixOS): sway, greetd + tuigreet
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

Installed by hand. `frieren` is LUKS + btrfs (`modules/hosts/frieren/disko.nix`) on a Root partition next to the Asahi ESP.

> [!TIP]
> ^. .^₎Ⳋ&nbsp;&nbsp;Before you begin: make sure you have a reliable external backup of your macOS data.

1. From macOS, run `curl https://alx.sh | sh`, choose the UEFI-only environment, and leave free space for NixOS. Boot a NixOS live environment (the nixos-apple-silicon installer ISO).
2. Create the Root partition in the free space, then format it with the UUID `disko.nix` pins and let disko lay down the subvolumes:
   ```bash
   cryptsetup luksFormat --type luks2 --uuid a0c92d69-f406-4dc1-89af-000fc1ac204e /dev/<root>
   cryptsetup open --allow-discards /dev/<root> cryptroot
   nix run github:nix-community/disko -- --mode format,mount --flake .#frieren
   mount -o fmask=0022,dmask=0022 /dev/disk/by-uuid/8622-1808 /mnt/boot
   ```
   If the ESP's UUID differs, update `hardware-configuration.nix`.
3. Put the `frieren` `id_ed25519` at `/mnt/home/apothecary/.ssh/` (agenix decrypts with it, and it fetches `asahi-firmware`), then `nixos-install --flake .#frieren --no-root-passwd` and set the user password with `nixos-enter`.

When nixos-apple-silicon release notes request new device firmware, run the stock `curl https://alx.sh | sh` and choose **Rebuild vendor firmware package**. Copy the resulting `vendorfw/firmware.cpio` into the private `asahi-firmware` input and update its lock before rebuilding NixOS. This is currently required for ambient-light sensor calibration.
