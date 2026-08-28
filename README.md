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

`frieren` uses an ephemeral root on top of encrypted btrfs. The `@` subvolume wipes on every boot. Only `/nix`, `/persist`, and `/var/log` survive.

Passwords are declarative (`mutableUsers = false`), reading from hashes on `/persist`. Firmware comes from a private flake input (`asahi-firmware`). Fetching it requires the SSH key to be loaded during installation, and agenix needs the same private-key file provisioned under `/persist` before `nixos-install` runs.

> [!TIP]
> ^. .^₎Ⳋ&nbsp;&nbsp;Before you begin: make sure you have a reliable external backup of your macOS data. While resizing APFS containers is generally safe, low-level partitioning always carries minor risks.

1. **Shrink macOS and install Asahi UEFI**
   Run `curl https://alx.sh | sh` in macOS. Choose **UEFI environment only (m1n1 + U-Boot + ESP)**. Follow the prompts to bless the bootloader and reboot.

   When nixos-apple-silicon release notes request new device firmware, run the installer again and choose **Rebuild vendor firmware package**. Copy the resulting `vendorfw/firmware.cpio` into the private `asahi-firmware` input and update its lock before rebuilding NixOS. This is currently required for ambient-light sensor calibration.

2. **Boot the NixOS installer**
   Flash the `nixos-apple-silicon` installer to a USB, boot from U-Boot, and connect to Wi-Fi (`iwctl station wlan0 connect <SSID>`).

3. **Partition the drive**

> [!CAUTION]
> (•˕ •マ.ᐟ&nbsp;&nbsp;**Do not touch any existing partitions.** This includes both Apple's system containers and the EFI/ESP partition created by the Asahi installer. Only use the unallocated free space.

   Use `fdisk` to create a new Linux root partition in the free space. Run `lsblk -f` and note the new partition path (e.g., `/dev/nvme0n1p6`) and the ESP's FAT UUID.

4. **Update the flake paths**
   Clone this repo to `/tmp/nix-config`. Update `modules/hosts/frieren/disko.nix` with your raw root partition path, and `modules/hosts/frieren/hardware-configuration.nix` with the ESP UUID.

5. **Format and mount (disko)**
   Run disko to create the LUKS container and btrfs subvolumes:
   ```bash
   sudo nix --experimental-features 'nix-command flakes' run github:nix-community/disko/latest -- --mode destroy,format,mount --flake .#frieren
   ```
   The ESP is untouched by disko. Mount it manually: `sudo mount /dev/disk/by-uuid/<ESP FAT UUID> /mnt/boot`

6. **Snapshot the blank root**
   *Required for the ephemeral rollback.*
   ```bash
   sudo mkdir -p /mnt2
   sudo mount -o subvol=/ /dev/mapper/cryptroot /mnt2
   sudo btrfs subvolume snapshot -r /mnt2/@ /mnt2/@-blank
   sudo umount /mnt2
   ```

7. **Set declarative passwords and provision the agenix identity**
   *All are written to `/persist`, which is available during early activation.*
   ```bash
   sudo mkdir -p /mnt/persist/passwords
   mkpasswd -m yescrypt | sudo tee /mnt/persist/passwords/apothecary
   mkpasswd -m yescrypt | sudo tee /mnt/persist/passwords/root
   sudo chmod 600 /mnt/persist/passwords/apothecary /mnt/persist/passwords/root
   sudo install -D -m 600 /path/to/frieren-id_ed25519 /mnt/persist/home/apothecary/.ssh/id_ed25519
   sudo chown -R 1000:100 /mnt/persist/home/apothecary
   ```

   Use the private key matching `frieren` in `secrets.nix`. Loading it into `ssh-agent` is also necessary for fetching the private firmware input, but the agent alone is not sufficient for agenix.

8. **Install NixOS**
   Ensure your SSH key is loaded so the flake can fetch the private firmware input, then run:
   ```bash
   sudo nixos-install --flake .#frieren --no-root-passwd
   sudo reboot
   ```

9. **First boot & restore**
   Log in. Because the `preservation` module uses bind mounts, `~/.ssh`, `~/.gnupg`, and `~/.password-store` are wired directly to `/persist`. The SSH identity is already present from installation; copy the remaining GPG material into `~/.gnupg` and clone the password store into `~/.password-store`. They will automatically survive the next reboot.

   Update the repo's `disko.nix` with the new LUKS UUID (`sudo cryptsetup luksUUID /dev/nvme0n1pN`) for future rebuilds.
