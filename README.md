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

`frieren` is installed the way Fedora is on Apple Silicon: the Asahi Installer writes a finished system image into a new partition, so the first boot is already NixOS with this config. Nothing is downloaded from GitHub and no USB stick is needed.

> [!TIP]
> ^. .^₎Ⳋ&nbsp;&nbsp;Before you begin: make sure you have a reliable external backup of your macOS data. The installer shrinks the macOS container to make room for the new partitions.

> [!WARNING]
> The frieren image is **not encrypted**. Disk encryption (`disko.nix`) needs a passphrase at install time, which an image can't hold. The LUKS layout is still there for the live-environment install path (`frieren-install`).

1. **Build the image** (needs the aarch64-linux builder in `modules/system/nix.nix`):
   ```bash
   nix build .#packages.aarch64-linux.frieren-asahi-image -o frieren-image
   ```

2. **From macOS:** run the Asahi wrapper with that build. It is the official `alx.sh` bootstrap, reading the image from that directory. First it asks for the frieren password, the path to the `frieren` `id_ed25519`, and a Wi-Fi network, and bundles `~/nix-config`. Then it runs the Asahi Installer, which installs the image into a new 2.5 GB macOS stub container and new EFI and Root partitions, and leaves the existing partitions alone.
   ```bash
   sh modules/hosts/frieren/asahi.sh ./frieren-image
   ```
   Choose `f` (free space), **NixOS frieren**, the size, and a name. When the Mac shuts down, wait 25 s, hold the power button, pick the new OS, and finish in recoveryOS.

3. **First boot:** `frieren-first-boot` applies what `asahi.sh` collected, then deletes it from the ESP: password, key, Wi-Fi, `~/nix-config` (cloned, with the original remotes), and a pass of agenix. The greeter comes up with everything in place. Anything left blank in `asahi.sh` is asked for on tty1 instead.

4. **Rebuilding:** the installed machine is `nixosConfigurations.frieren` (ext4 root), so plain `nh os switch` is right. The LUKS + btrfs layout is `frieren-luks`, for `frieren-install` only.

When nixos-apple-silicon release notes request new device firmware, run the stock `curl https://alx.sh | sh` and choose **Rebuild vendor firmware package**. Copy the resulting `vendorfw/firmware.cpio` into the private `asahi-firmware` input and update its lock before rebuilding NixOS. This is currently required for ambient-light sensor calibration.
