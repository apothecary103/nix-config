#!/bin/sh
# Stage 1 of the frieren install, run from macOS:
#   curl -L https://raw.githubusercontent.com/apothecary103/nix-config/main/modules/hosts/frieren/asahi.sh | sh
#
# alx.sh, but the upstream installer is handed an OS list with a single
# "NixOS (frieren)" entry: the current UEFI-only ESP plus an empty Root
# partition taking the rest of the space, which `nix run .#frieren-install`
# then encrypts and installs into.

# Truncation guard
if true; then
    set -e

    if [ ! -e /System ]; then
        echo "This stage runs from macOS (or recoveryOS)."
        exit 1
    fi

    export LC_ALL=en_US.UTF-8
    export LANG=en_US.UTF-8
    export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

    export VERSION_FLAG=https://cdn.asahilinux.org/installer/latest
    export INSTALLER_BASE=https://cdn.asahilinux.org/installer
    export INSTALLER_DATA=https://github.com/AsahiLinux/asahi-installer-data/raw/prod/data/installer_data.json
    export INSTALLER_DATA_ALT=https://alx.sh/installer_data.json
    export REPO_BASE=https://cdn.asahilinux.org
    export DISTRO=NixOS
    export DISTRO_DOCS=https://github.com/apothecary103/nix-config#fresh-install-nixos--asahi

    # The FAT serial modules/hosts/frieren/hardware-configuration.nix mounts
    # /boot by (8622-1808), fixed here so a reinstall needs no repo edit.
    ESP_VOLUME_ID=0x86221808

    TMP=/tmp/asahi-install

    echo
    echo "Bootstrapping installer:"

    if [ -e "$TMP" ]; then
        mv "$TMP" "$TMP-$(date +%Y%m%d-%H%M%S)"
    fi

    mkdir -p "$TMP"
    cd "$TMP"

    PKG_VER="$(curl --no-progress-meter -L "$VERSION_FLAG")"
    echo "  Version: $PKG_VER"
    PKG="installer-$PKG_VER.tar.gz"

    echo "  Downloading..."
    curl --no-progress-meter -L -o "$PKG" "$INSTALLER_BASE/$PKG"
    if ! curl --no-progress-meter -L -o upstream_data.json "$INSTALLER_DATA"; then
        curl --no-progress-meter -L -o upstream_data.json "$INSTALLER_DATA_ALT"
    fi

    echo "  Extracting..."
    tar xf "$PKG"

    echo "  Writing the NixOS OS list..."
    # The installer bundles its own Python; macOS no longer ships one.
    DYLD_LIBRARY_PATH=$PWD/Frameworks/Python.framework/Versions/Current/lib \
    DYLD_FRAMEWORK_PATH=$PWD/Frameworks \
    Frameworks/Python.framework/Versions/Current/bin/python3 -I - "$ESP_VOLUME_ID" <<'EOF'
import json, sys

with open("upstream_data.json") as f:
    data = json.load(f)

# Track upstream's current UEFI-only package (m1n1 + U-Boot + ESP contents)
# rather than pinning a zip name that goes stale with every Asahi release.
uefi = next(
    o for o in data["os_list"]
    if o["name"].startswith("UEFI environment only") and not o.get("expert")
)
esp = dict(uefi["partitions"][0], volume_id=sys.argv[1])

data["os_list"] = [dict(
    uefi,
    name="NixOS (frieren)",
    default_os_name="NixOS",
    partitions=[
        esp,
        {"name": "Root", "type": "Linux", "size": "32GB", "expand": True},
    ],
)]

with open("installer_data.json", "w") as f:
    json.dump(data, f)
EOF

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
