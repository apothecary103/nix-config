#!/bin/sh
# Installs frieren from macOS with the Asahi Installer: a finished NixOS system
# image, the same way the Fedora images are installed. Nothing is downloaded
# from GitHub; the image comes from this repo's build on your Mac.
#
#   nix build .#packages.aarch64-linux.frieren-asahi-image -o frieren-image
#   sh modules/hosts/frieren/asahi.sh ./frieren-image
#
# The installer creates a new EFI and Root partition from free space it makes
# by shrinking macOS. It does not modify the existing partitions, including
# the EFI - NIXOS and Linux Filesystem partitions already on the disk.

# Truncation guard
if true; then
    set -e

    if [ ! -e /System ]; then
        echo "This stage runs from macOS (or recoveryOS)."
        exit 1
    fi

    if [ -z "${1:-}" ] || [ ! -f "$1/frieren-asahi-image.zip" ] || [ ! -f "$1/installer_data.json" ]; then
        echo "usage: sh asahi.sh <dir>"
        echo "  <dir> holds frieren-asahi-image.zip and installer_data.json, from:"
        echo "  nix build .#packages.aarch64-linux.frieren-asahi-image -o frieren-image"
        exit 1
    fi
    IMAGE_DIR=$(cd "$1" && pwd -P)

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

    TMP=/tmp/asahi-install

    echo
    echo "Bootstrapping installer:"

    if [ -e "$TMP" ]; then
        mv "$TMP" "$TMP-$(date +%Y%m%d-%H%M%S)"
    fi

    mkdir -p "$TMP/repo/os"
    cd "$TMP"

    PKG_VER="$(curl --no-progress-meter -fL "$VERSION_FLAG")"
    if [ -z "$PKG_VER" ]; then
        echo "Could not get the Asahi Installer version from $VERSION_FLAG."
        exit 1
    fi
    echo "  Version: $PKG_VER"
    PKG="installer-$PKG_VER.tar.gz"

    echo "  Downloading the Asahi Installer..."
    curl --no-progress-meter -fL -o "$PKG" "$INSTALLER_BASE/$PKG"

    echo "  Extracting..."
    tar xf "$PKG"

    # The installer reads a package whose name is not a URL from REPO_BASE/os/.
    ln -s "$IMAGE_DIR/frieren-asahi-image.zip" repo/os/frieren-asahi-image.zip
    cp "$IMAGE_DIR/installer_data.json" installer_data.json
    export REPO_BASE="$TMP/repo"

    echo "  Initializing..."
    echo

    if [ "$USER" != "root" ]; then
        echo "The installer needs to run as root."
        echo "Please enter your sudo password if prompted."
        exec caffeinate -dis sudo -E ./install.sh
    else
        exec caffeinate -dis ./install.sh
    fi
fi
