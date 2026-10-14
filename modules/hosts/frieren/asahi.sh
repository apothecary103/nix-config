#!/bin/sh
# SPDX-License-Identifier: MIT
# Installs frieren from macOS with the Asahi Installer: a finished NixOS system
# image, the same way the Fedora images are installed. This is the official
# bootstrap (https://alx.sh) with two changes:
#
#   - the installer data and the OS package come from <dir> on this Mac
#     instead of the Asahi CDN;
#   - before the installer starts, this asks for what the first boot needs
#     (password, frieren key, Wi-Fi) and bundles ~/nix-config. When the
#     installer shuts the Mac down, a `shutdown` hook copies that seed onto
#     the new ESP. The first boot applies it (image.nix) and comes up at the
#     greeter with Wi-Fi, secrets and the repo in place.
#
#   nix build .#packages.aarch64-linux.frieren-asahi-image -o frieren-image
#   sh modules/hosts/frieren/asahi.sh ./frieren-image
#
# Environment: FRIEREN_KEY (path to the frieren id_ed25519), FRIEREN_REPO
# (default ~/nix-config).

# Truncation guard
if true; then
    set -e

    if [ ! -e /System ]; then
        echo "You appear to be running this script from Linux or another non-macOS system."
        echo "frieren can only be installed from macOS (or recoveryOS)."
        exit 1
    fi

    if [ -z "${1:-}" ] || [ ! -f "$1/frieren-asahi-image.zip" ] || [ ! -f "$1/installer_data.json" ]; then
        echo "usage: sh asahi.sh <dir>"
        echo "  <dir> holds frieren-asahi-image.zip and installer_data.json, from:"
        echo "  nix build .#packages.aarch64-linux.frieren-asahi-image -o frieren-image"
        exit 1
    fi
    IMAGE_DIR=$(cd "$1" && pwd -P)
    shift

    # The installer reads data["os_list"]; a bare OS entry crashes it.
    if ! grep -q '"os_list"' "$IMAGE_DIR/installer_data.json"; then
        echo "$IMAGE_DIR/installer_data.json has no os_list; rebuild the image."
        exit 1
    fi

    export LC_ALL=en_US.UTF-8
    export LANG=en_US.UTF-8
    export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

    export VERSION_FLAG=https://cdn.asahilinux.org/installer/latest
    export INSTALLER_BASE=https://cdn.asahilinux.org/installer

    # The public half of the frieren entry in secrets.nix: agenix decrypts
    # with this key, and it fetches the private asahi-firmware input.
    FRIEREN_PUB="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJMTySSX9bqz5ewfXQhOpqjLkX5Ch/j9060Za2i8So9D"
    REPO=${FRIEREN_REPO:-$HOME/nix-config}

    TMP=/tmp/asahi-install
    SEED="$TMP/seed"

    # A seed left behind by an aborted run holds the key; drop it.
    rm -rf /tmp/asahi-install*/seed 2>/dev/null || true

    echo
    echo "Bootstrapping installer:"

    if [ -e "$TMP" ]; then
        mv "$TMP" "$TMP-$(date +%Y%m%d-%H%M%S)"
    fi

    mkdir -p "$TMP/repo/os"
    (umask 077 && mkdir "$SEED")
    cd "$TMP"

    trap 'stty echo 2>/dev/null; rm -rf "$SEED"; exit 1' INT TERM

    # Older images ask on tty1 and would leave a seed on the ESP for good.
    if ! grep -q '"frieren_seed"' "$IMAGE_DIR/installer_data.json"; then
        echo
        echo "This image predates the first-boot seed: the first boot asks for the"
        echo "password and key on tty1, and Wi-Fi is set up there with nmtui."
        rm -rf "$SEED"
    fi

    if [ -d "$SEED" ]; then
        echo
        echo "First-boot setup (copied to the new ESP, deleted on the first boot):"
        echo

        # The password is stored only as a SHA-512 crypt hash. macOS's LibreSSL
        # has no `passwd -6`, so the hash comes from the flake's nixpkgs.
        while :; do
            stty -echo 2>/dev/null || true
            printf "  Password for apothecary on frieren: "; read -r pw1; echo
            printf "  Again: "; read -r pw2; echo
            stty echo 2>/dev/null || true
            if [ -z "$pw1" ]; then
                echo "  Empty; it will be asked on the first boot instead."
                break
            fi
            if [ "$pw1" != "$pw2" ]; then
                echo "  They do not match. Try again."
                continue
            fi
            if printf '%s\n' "$pw1" | nix --extra-experimental-features 'nix-command flakes' \
                shell --inputs-from "$REPO" nixpkgs#openssl -c openssl passwd -6 -stdin \
                >"$SEED/password.hash" 2>/dev/null && [ -s "$SEED/password.hash" ]; then
                echo "  Password hashed."
            else
                rm -f "$SEED/password.hash"
                echo "  Could not hash it (needs nix and $REPO); it will be asked on the first boot."
            fi
            break
        done
        pw1= pw2=

        # The frieren key. It must be the secrets.nix key and have no passphrase:
        # agenix cannot prompt for one at boot.
        key=${FRIEREN_KEY:-}
        while :; do
            if [ -z "$key" ]; then
                printf "  Path to the frieren id_ed25519 (empty: paste it on the first boot): "
                read -r key
                [ -n "$key" ] || break
            fi
            case "$key" in "~/"*) key="$HOME/${key#\~/}" ;; esac
            have=$(ssh-keygen -y -P "" -f "$key" 2>/dev/null | cut -d' ' -f1,2 || true)
            if [ "$have" = "$FRIEREN_PUB" ]; then
                cp "$key" "$SEED/id_ed25519"
                echo "  Key matches secrets.nix."
                break
            fi
            echo "  $key is not the frieren key from secrets.nix, or it has a passphrase."
            key=
        done

        # Host keys, so the first git pull and asahi-firmware fetch don't stop to ask.
        for h in codeberg.org github.com; do
            ssh-keygen -F "$h" 2>/dev/null | grep -v '^#' >>"$SEED/known_hosts" || true
        done

        # Wi-Fi, as a NetworkManager keyfile.
        printf "  Wi-Fi network name (empty: connect on frieren later): "
        read -r ssid
        if [ -n "$ssid" ]; then
            stty -echo 2>/dev/null || true
            printf "  Wi-Fi password for %s (empty: open network): " "$ssid"; read -r psk; echo
            stty echo 2>/dev/null || true
            mkdir -p "$SEED/system-connections"
            file="$SEED/system-connections/$(printf '%s' "$ssid" | tr -c 'A-Za-z0-9._-' '_').nmconnection"
            {
                printf '[connection]\nid=%s\ntype=wifi\nautoconnect=true\n\n' "$ssid"
                printf '[wifi]\nmode=infrastructure\nssid=%s\n\n' "$ssid"
                if [ -n "$psk" ]; then
                    printf '[wifi-security]\nkey-mgmt=wpa-psk\npsk=%s\n\n' "$psk"
                fi
                printf '[ipv4]\nmethod=auto\n\n[ipv6]\nmethod=auto\naddr-gen-mode=stable-privacy\n'
            } >"$file"
            psk=
            echo "  Wi-Fi saved."
        fi

        # The repo, as a git bundle of what is committed.
        if git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
            if [ -n "$(git -C "$REPO" status --porcelain)" ]; then
                echo "  Note: $REPO has uncommitted changes; only commits are copied."
            fi
            git -C "$REPO" bundle create -q "$SEED/nix-config.bundle" --all
            url=$(git -C "$REPO" remote get-url origin 2>/dev/null || true)
            if [ -n "$url" ]; then
                echo "fetch $url" >"$SEED/remotes"
                git -C "$REPO" remote get-url --push --all origin 2>/dev/null |
                    sed 's/^/push /' >>"$SEED/remotes" || true
            fi
            echo "  Repo bundled from $REPO."
        else
            echo "  No git repo at $REPO; clone it on frieren later."
        fi
    fi

    echo
    echo "  Checking version..."

    PKG_VER="$(curl --no-progress-meter -fL "$VERSION_FLAG")"
    if [ -z "$PKG_VER" ]; then
        echo "Could not get the Asahi Installer version from $VERSION_FLAG."
        exit 1
    fi
    echo "  Version: $PKG_VER"
    PKG="installer-$PKG_VER.tar.gz"

    echo "  Downloading..."
    curl --no-progress-meter -fL -o "$PKG" "$INSTALLER_BASE/$PKG"

    echo "  Extracting..."
    tar xf "$PKG"

    # The installer reads a package whose name is not a URL from REPO_BASE/os/.
    ln -s "$IMAGE_DIR/frieren-asahi-image.zip" repo/os/frieren-asahi-image.zip
    cp "$IMAGE_DIR/installer_data.json" installer_data.json
    export REPO_BASE="$TMP/repo"

    # install.sh puts $PWD/bin first on PATH, and the installer ends by
    # running `shutdown -h now` (or `shutdown -r now` from recoveryOS). This
    # hook copies the seed onto the new ESP first: the one FAT32 partition
    # whose serial is 8622-1808, the volume_id in installer_data.json. It never
    # blocks the shutdown; without a seed, the first boot asks instead.
    mkdir -p bin
    printf '#!/bin/sh\nSEED="%s"\n' "$SEED" >bin/shutdown
    cat >>bin/shutdown <<'EOF'
copy_seed() {
    [ -d "$SEED" ] || return 0
    esps=""
    for part in $(diskutil list | awk '$2 == "EFI" && $NF ~ /^disk[0-9]+s[0-9]+$/ { print $NF }'); do
        id=$(dd if="/dev/r$part" bs=512 count=1 2>/dev/null | xxd -s 67 -l 4 -p)
        [ "$id" = 08182286 ] && esps="$esps $part"
    done
    set -- $esps
    if [ "$#" -ne 1 ]; then
        echo "frieren: expected one ESP with ID 8622-1808, found $#; not copying the seed."
        echo "frieren: the first boot will ask for the password and key on tty1."
        return 1
    fi
    part=$1
    mounted=0
    mp=$(diskutil info "$part" | sed -n 's/^ *Mount Point: *//p')
    if [ -z "$mp" ]; then
        diskutil mount "$part" >/dev/null || return 1
        mounted=1
        mp=$(diskutil info "$part" | sed -n 's/^ *Mount Point: *//p')
    fi
    if [ -z "$mp" ] || [ ! -d "$mp/m1n1" ]; then
        echo "frieren: $part is not the new ESP; not copying the seed."
        return 1
    fi
    rm -rf "$mp/frieren-seed"
    cp -R "$SEED" "$mp/frieren-seed" || return 1
    sync
    [ "$mounted" = 1 ] && diskutil unmount "$part" >/dev/null
    echo "frieren: first-boot seed copied to $part."
}
copy_seed || true
rm -rf "$SEED"
exec /sbin/shutdown "$@"
EOF
    chmod 755 bin/shutdown

    echo "  Initializing..."
    echo

    if [ "$USER" != "root" ]; then
        echo "The installer needs to run as root."
        echo "Please enter your sudo password if prompted."
        exec caffeinate -dis sudo -E ./install.sh "$@"
    else
        exec caffeinate -dis ./install.sh "$@"
    fi
fi
