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

### Day-to-day rebuilds

Once a host is installed, rebuilds go through
[`nh`](https://github.com/nix-community/nh), which is already pointed at this
flake and handles GC/cleanup too:

```bash
# NixOS (frieren)
nh os switch

# macOS (fern)
nh darwin switch
```

home-manager is wired into the system rebuild (`modules/system/home-manager.nix`),
so there is no separate `home-manager switch` step.

### Fresh install (frieren, Asahi / Apple Silicon)

frieren is NixOS on bare Apple Silicon via
[`nixos-apple-silicon`](https://github.com/tpwrules/nixos-apple-silicon), with an
ephemeral root and home. Disko lays out an encrypted btrfs volume
(`modules/hosts/frieren/disko.nix`) whose `@` (root) subvolume is wiped back to a
blank snapshot on every boot (`modules/hosts/frieren/impermanence.nix`). `/home`
rides on `@`, so it is wiped too;
[preservation](https://github.com/nix-community/preservation) bind-mounts the
system state and the per-user secrets/state worth keeping back from `/persist`
(`modules/system/preservation.nix`). Only `/nix`, `/persist` and `/var/log` are
persistent subvolumes. Disko manages **only** that root partition; the EFI system
partition is left alone because on Asahi it also carries m1n1, U-Boot and vendor
firmware, and the GPT is never rewritten, so the Apple-owned partitions (iBoot,
recovery, macOS APFS) survive.

Worth knowing up front:

- **Firmware** comes from the private `asahi-firmware` flake input (an SSH
  codeberg repo) holding *this machine's* extracted vendor firmware. A reinstall
  is the same physical Mac, so that repo is still valid; you only need the SSH
  key loaded so the flake can fetch it. Re-extract only if the firmware actually
  changed (see the nixos-apple-silicon firmware docs).
- **Passwords are declarative.** `mutableUsers` is off, so `passwd` is disabled
  and login hashes are read from files on `/persist` (which survives the wipe).
  You write those once during install (step 7), not with `passwd` after boot.

1. **macOS, run the Asahi installer.** Free up disk space, then
   `curl https://alx.sh | sh` and choose **"UEFI environment only (m1n1 +
   U-Boot + ESP)"**. This shrinks macOS, creates the EFI system partition (the
   vfat that becomes `/boot`), and leaves the rest as free space. Complete the
   bootloader-blessing reboot it walks you through. The installer's exact wording
   changes over time, so follow the current
   [nixos-apple-silicon install guide](https://github.com/tpwrules/nixos-apple-silicon/blob/main/docs/uefi-standalone.md).

2. **Boot the installer image.** `dd` the nixos-apple-silicon installer image to
   a USB stick, then boot it from U-Boot. Bring up Wi-Fi with `iwctl`
   (`station wlan0 connect <SSID>`).

3. **Create the Linux root partition** in the free space the Asahi installer
   left, e.g. one partition filling the gap on `/dev/nvme0n1` via `fdisk` or such.
   Then note the values you'll need:

   ```bash
   lsblk -f      # -> new root partition (e.g. /dev/nvme0n1p6) + the ESP's FAT UUID
   ```

   ⚠️ Only add/format the new Linux partition. Do not touch the ESP or the
   Apple-owned partitions.

4. **Point the config at the real devices** (clone this flake somewhere
   writable, e.g. `git clone … /tmp/nix-config`):

   - `modules/hosts/frieren/disko.nix`, set `disko.devices.disk.root.device` to
     the raw root partition (e.g. `/dev/nvme0n1p6`). The committed value is a
     `by-uuid`, which only exists *after* the LUKS container is created.
   - `modules/hosts/frieren/hardware-configuration.nix`, set
     `fileSystems."/boot".device` to `/dev/disk/by-uuid/<new ESP FAT UUID>`.

5. **Format and mount with disko.** This creates LUKS `cryptroot`, the btrfs
   subvolumes (`@`, `@nix`, `@persist`, `@log`, `@swap`), the `/swap/swapfile`,
   and mounts everything under `/mnt`. It prompts for the new LUKS passphrase:

   ```bash
   sudo nix --experimental-features 'nix-command flakes' run \
     github:nix-community/disko/latest -- \
     --mode disko --flake .#frieren
   ```

   The ESP is not managed by disko, so mount it by hand:

   ```bash
   sudo mount /dev/disk/by-uuid/<ESP FAT UUID> /mnt/boot
   ```

6. **Snapshot the blank root.** The boot-time rollback restores `@` from a
   read-only `@-blank` snapshot, so create it now while `@` is still empty
   (mount the btrfs top level to make the snapshot a sibling of `@`, not a child
   of it):

   ```bash
   sudo mkdir -p /mnt2
   sudo mount -o subvol=/ /dev/mapper/cryptroot /mnt2
   sudo btrfs subvolume snapshot -r /mnt2/@ /mnt2/@-blank
   sudo umount /mnt2
   ```

7. **Write the persisted password hashes.** `mutableUsers = false` reads these at
   first activation, so they must exist before install. They live on `/persist`,
   which the wipe never touches:

   ```bash
   sudo mkdir -p /mnt/persist/passwords
   mkpasswd -m sha-512 | sudo tee /mnt/persist/passwords/apothecary
   mkpasswd -m sha-512 | sudo tee /mnt/persist/passwords/root
   sudo chmod 600 /mnt/persist/passwords/apothecary /mnt/persist/passwords/root
   ```

8. **Install.** The flake fetches the private `asahi-firmware` input over SSH, so
   load the key with codeberg access first (`ssh-add`, or copy it into the
   installer):

   ```bash
   sudo nixos-install --flake .#frieren --no-root-passwd
   sudo reboot
   ```

9. **First boot.** greetd + tuigreet comes up. Log in as `apothecary` with the
   password you set and pick Hyprland or Niri. Because home is ephemeral, your
   secrets and long-lived state live on `/persist` and are bind-mounted back into
   `~` (see the `users.apothecary` list in `modules/system/preservation.nix`).
   On a clean disk those start empty, so restore your GPG key, `pass` store and
   SSH keys into `/persist/home/apothecary/{.gnupg,.password-store,.ssh}` (you
   can do this during install under `/mnt/persist/...`). Anything in `~` that is
   not on that list, or regenerated by home-manager, is wiped on every reboot.
   From here, rebuilds are just `nh os switch`.

> After install, grab the new LUKS UUID
> (`sudo cryptsetup luksUUID /dev/nvme0n1pN`) and set
> `disko.devices.disk.root.device` back to `/dev/disk/by-uuid/<that>`, so the
> committed config uses a stable reference and matches the original style.
