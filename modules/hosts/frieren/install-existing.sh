#!/usr/bin/env bash
# Installs frieren onto an Asahi Linux that is already on this Mac's internal
# disk. Two ways to pick where it goes:
#
#   --target PARTUUID   an existing Linux partition (your base install). Its
#                       contents are destroyed; the partition is reformatted.
#   (no --target)       unallocated space on the same disk, as a new partition.
#
# macOS data is protected in every mode:
#   - Apple partition types (APFS, HFS+, Apple boot, recovery, UFS) are listed
#     as PROTECTED and are refused as targets.
#   - The ESP (the partition mounted at /boot in the flake) is never a target;
#     it is only mounted and written by the bootloader install.
#   - The target must be on the same disk as the ESP and must not be mounted.
#   - In the no-target mode the GPT is saved before the one partition is added,
#     and every existing entry is compared against a snapshot after the write;
#     any change restores the backup and stops.
#   - Nothing is written before the plan is shown and "frieren" is typed.
#
#   sudo bash install-existing.sh --key ~/frieren-id_ed25519 --target PARTUUID [--flake-dir DIR] [--dry-run]
#   sudo bash install-existing.sh --key ~/frieren-id_ed25519 [--flake-dir DIR] [--dry-run]
set -euo pipefail

readonly CONFIRM_WORD=frieren
readonly PART_LABEL=Frieren
readonly SECTOR=512
readonly ALIGN=2048 # 1 MiB, in sectors
readonly MIN_BYTES=$((32 * 1024 * 1024 * 1024))
readonly REPO=https://github.com/apothecary103/nix-config
readonly LINUX_TYPE=0fc63daf-8483-4772-8e79-3d69d8477de4
readonly LINUX_LUKS_TYPE=8309
readonly BACKUP_DIR=/root/frieren-install
# Apple partition types, lowercase as lsblk prints them: APFS, HFS+,
# Apple boot, Apple recovery, Apple UFS.
readonly APPLE_TYPES=(
  7c3457ef-0000-11aa-aa11-00306543ecac
  48465300-0000-11aa-aa11-00306543ecac
  426f6f74-0000-11aa-aa11-00306543ecac
  52637672-0000-11aa-aa11-00306543ecac
  55465300-0000-11aa-aa11-00306543ecac
)
readonly TOOLS=(sgdisk sfdisk parted lsblk blkid wipefs findmnt cryptsetup ssh-keygen git jq udevadm partprobe nix nixos-install nixos-enter)

die() {
  echo "error: $*" >&2
  exit 1
}
log() { echo "==> $*"; }

key=""
flake_dir=""
target_partuuid=""
dry_run=0
while [ $# -gt 0 ]; do
  case "$1" in
    --key) key=${2:?--key needs a path}; shift 2 ;;
    --flake-dir) flake_dir=${2:?--flake-dir needs a path}; shift 2 ;;
    --target) target_partuuid=${2:?--target needs a PARTUUID}; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    -h | --help)
      sed -n '2,20p' "$0"
      exit 0
      ;;
    *) die "unknown argument: $1" ;;
  esac
done

[ "$(id -u)" -eq 0 ] || die "run as root (sudo)"
[ -e /proc/device-tree/chosen/asahi,efi-system-partition ] ||
  die "this is not an Asahi Linux system"
[ -n "$key" ] || die "--key is required (the frieren id_ed25519)"
[ -f "$key" ] || die "key not found: $key"
key=$(realpath "$key")

# Re-run inside a shell that has the tools when the base system lacks them.
missing=()
for t in "${TOOLS[@]}"; do command -v "$t" >/dev/null || missing+=("$t"); done
if [ "${#missing[@]}" -gt 0 ]; then
  [ -z "${FRIEREN_IN_NIX_SHELL:-}" ] || die "still missing: ${missing[*]}"
  command -v nix >/dev/null || die "missing ${missing[*]}; install nix first, then rerun"
  log "fetching tools: ${missing[*]}"
  exec env FRIEREN_IN_NIX_SHELL=1 nix --extra-experimental-features 'nix-command flakes' shell \
    nixpkgs#gptfdisk nixpkgs#parted nixpkgs#util-linux nixpkgs#cryptsetup nixpkgs#openssh \
    nixpkgs#git nixpkgs#jq nixpkgs#coreutils nixpkgs#gnugrep nixpkgs#gawk \
    nixpkgs#nixos-install-tools \
    --command "$0" "$@"
fi

# The git+ssh asahi-firmware input is fetched with the frieren key, the same
# key nixos-install needs to decrypt agenix secrets.
export GIT_SSH_COMMAND="ssh -i $key -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
export NIX_CONFIG="experimental-features = nix-command flakes"

if [ -z "$flake_dir" ]; then
  flake_dir=$(mktemp -d /tmp/frieren-flake.XXXXXX)
  log "cloning $REPO (GitHub main; uncommitted changes need --flake-dir)"
  git clone --depth 1 "$REPO" "$flake_dir" >/dev/null
fi
flake_dir=$(realpath "$flake_dir")

# Everything install-time comes from the flake, so the ESP, LUKS UUID, LUKS
# name and user stay in sync with hardware-configuration.nix and disko.nix.
cfg="$flake_dir#nixosConfigurations.frieren.config"
esp_partuuid=$(nix eval --raw "$cfg.fileSystems.\"/boot\".device" | sed 's#.*/##')
luks_uuid=$(nix eval --raw "$cfg.disko.devices.disk.root.device" | sed 's#.*/##')
luks_name=$(nix eval --raw "$cfg.disko.devices.disk.root.content.name")
user=$(nix eval --json "$cfg.hjem.users" --apply builtins.attrNames | jq -r '.[0]')

# The frieren line in secrets.nix is the only key that can decrypt frieren's
# secrets, so it must be the key we were given.
want_pub=$(sed -n 's/^ *frieren = "\(ssh-ed25519 [^"]*\)";/\1/p' "$flake_dir/secrets.nix")
have_pub=$(ssh-keygen -y -f "$key")
[ -n "$want_pub" ] || die "no frieren key in secrets.nix"
[ "$have_pub" = "$want_pub" ] || die "$key is not the frieren key from secrets.nix"

is_apple_type() {
  local t=${1,,} a
  for a in "${APPLE_TYPES[@]}"; do [ "$t" = "$a" ] && return 0; done
  return 1
}

# The ESP, found by the PARTUUID the flake mounts at /boot.
esp=$(lsblk -rno PATH,PARTUUID | awk -v u="$esp_partuuid" 'tolower($2) == u { print $1 }')
[ -n "$esp" ] || die "no partition with PARTUUID $esp_partuuid (the ESP); check the disk"
[ "$(wc -l <<<"$esp")" -eq 1 ] || die "more than one partition matches the ESP PARTUUID"
disk=/dev/$(lsblk -no PKNAME "$esp")
[ "$(blkid -p -o value -s PTTYPE "$disk")" = gpt ] || die "$disk is not GPT"

echo "Partitions on $disk:"
while read -r path ptype plabel; do
  [ -n "$path" ] || continue
  mark=""
  is_apple_type "$ptype" && mark="PROTECTED (macOS)"
  [ "$path" = "$esp" ] && mark="ESP (kept; bootloader only)"
  printf '  %-18s %-38s %-14s %s\n' "$path" "$ptype" "${plabel:-}" "$mark"
done < <(lsblk -rno PATH,PARTTYPE,PARTLABEL "$disk" | awk -v d="$disk" 'index($1, d) == 1 && $1 != d { print }')
echo

mode=""
if [ -n "$target_partuuid" ]; then
  mode=existing
  target=$(lsblk -rno PATH,PARTUUID | awk -v u="$target_partuuid" 'tolower($2) == tolower(u) { print $1 }')
  [ -n "$target" ] || die "no partition with PARTUUID $target_partuuid"
  [ "$(lsblk -no PKNAME "$target")" = "${disk#/dev/}" ] || die "$target is not on $disk (the ESP's disk)"
  [ "$target" != "$esp" ] || die "$target is the ESP; it is never a target"
  ttype=$(lsblk -dno PARTTYPE "$target")
  is_apple_type "$ttype" && die "$target is an Apple (macOS) partition; refusing"
  [ "${ttype,,}" = "$LINUX_TYPE" ] || die "$target is not a Linux filesystem partition (type $ttype); refusing"
  [ -z "$(findmnt -rn -S "$target" || true)" ] || die "$target is mounted; unmount it first"
  current=$(blkid -p -o value -s TYPE "$target" 2>/dev/null || true)
  size=$(lsblk -dno SIZE "$target")
  echo "Plan: DESTROY the existing contents of $target ($size, currently: ${current:-no filesystem})"
  echo "      and install frieren there (LUKS UUID $luks_uuid, btrfs from disko.nix)."
  echo "      This is your base Linux install. There is no backup of it."
else
  mode=new
  # The largest unallocated region, aligned, in sectors. parted prints free
  # rows with a number and the word "free" in field 5.
  free=$(parted -sm "$disk" unit s print free | awk -F: '$5 ~ /^free/ { gsub(/s/, "", $2); gsub(/s/, "", $3); print $2, $3 }' |
    while read -r start end; do
      start=$(( (start + ALIGN - 1) / ALIGN * ALIGN ))
      [ "$end" -gt "$start" ] && echo "$start $end $(( (end - start + 1) * SECTOR ))"
    done | sort -k3 -n | tail -1)
  [ -n "$free" ] || die "no unallocated space on $disk; pass --target to use an existing Linux partition"
  read -r fstart fend fbytes <<<"$free"
  [ "$fbytes" -ge "$MIN_BYTES" ] || die "largest free region is $((fbytes / 1024 / 1024 / 1024)) GiB; need 32 GiB"
  echo "Plan: create a new partition 'Frieren' at sectors $fstart-$fend ($((fbytes / 1024 / 1024 / 1024)) GiB of free space),"
  echo "      then install frieren there (LUKS UUID $luks_uuid, btrfs from disko.nix)."
fi
echo "Nothing else is written. The ESP is updated by the bootloader install only."
echo "Reboot is not automatic."
echo

if [ "$dry_run" -eq 1 ]; then
  log "dry run: nothing written"
  exit 0
fi

read -rp "Type $CONFIRM_WORD to continue: " confirm
[ "$confirm" = "$CONFIRM_WORD" ] || die "not confirmed; nothing written"

mounted_root=0
luks_open=0
snapshot=""
backup=""
cleanup() {
  set +e
  [ "$mounted_root" -eq 1 ] && umount -R /mnt
  [ "$luks_open" -eq 1 ] && cryptsetup close "$luks_name"
  [ -n "$snapshot" ] && rm -f "$snapshot"
}
trap cleanup EXIT

if [ "$mode" = new ]; then
  snapshot=$(mktemp)
  sfdisk -d "$disk" | grep ' : start=' | sort >"$snapshot"
  mkdir -p "$BACKUP_DIR"
  backup="$BACKUP_DIR/gpt-before-$(date +%Y%m%d-%H%M%S).bin"
  sgdisk -b "$backup" "$disk" >/dev/null
  log "GPT backup: $backup"

  log "creating partition Frieren"
  sgdisk -n "0:$fstart:$fend" -t "0:$LINUX_LUKS_TYPE" -c "0:$PART_LABEL" "$disk" >/dev/null
  partprobe "$disk"
  udevadm settle

  target=$(lsblk -rno PATH,PARTLABEL "$disk" | awk -v l="$PART_LABEL" '$2 == l { print $1 }')
  [ -n "$target" ] || die "the new partition did not appear; GPT backup is $backup"

  # Every entry that existed before must be unchanged; only the new partition
  # may appear. Anything else restores the backup and stops.
  after=$(mktemp)
  sfdisk -d "$disk" | grep ' : start=' | sort >"$after"
  if ! diff <(grep -vF "$target :" "$snapshot") <(grep -vF "$target :" "$after") >/dev/null ||
    ! grep -qF "$target :" "$after"; then
    rm -f "$after"
    sgdisk --load-backup="$backup" "$disk" >/dev/null
    partprobe "$disk"
    die "partition table changed beyond the new partition; restored $backup"
  fi
  rm -f "$after"
  log "existing partitions unchanged"
  [ -z "$(wipefs -n "$target" 2>/dev/null || true)" ] || die "$target is not blank"
fi

log "LUKS on $target"
cryptsetup luksFormat --type luks2 --uuid "$luks_uuid" "$target"
cryptsetup open --allow-discards "$target" "$luks_name"
luks_open=1
udevadm settle

log "btrfs layout from disko.nix"
nix run "$flake_dir#disko" -- --mode format,mount --flake "$flake_dir#frieren"
mounted_root=1

mkdir -p /mnt/boot
mount -o fmask=0022,dmask=0022 "$esp" /mnt/boot

install -D -m 600 "$key" "/mnt/home/$user/.ssh/id_ed25519"
ssh-keygen -y -f "$key" >"/mnt/home/$user/.ssh/id_ed25519.pub"

log "nixos-install"
nixos-install --flake "$flake_dir#frieren" --no-root-passwd --no-channel-copy

cp -a "$flake_dir" "/mnt/home/$user/nix-config"
nixos-enter --root /mnt -c "chown -R $user:users /home/$user"
echo "Password for $user:"
until nixos-enter --root /mnt -c "passwd $user"; do :; done

log "done; reboot when you are ready"
