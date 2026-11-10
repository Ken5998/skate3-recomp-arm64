#!/usr/bin/env bash
# Builds the ARM64 sysroot the build downloads on a handheld: an Ubuntu 24.04
# arm64 root with glibc, GCC 14's libstdc++ and the X11, Wayland, GTK 3 and
# audio development files, plus the pkgconf and wayland-scanner the build
# runs. It is pinyon-shift-arm64's sysroot with GTK 3 added (Skate 3
# Recomp's ReXGlue SDK opens its Linux window through GTK 3), and lets an
# image-based system such as ArmadaOS build the game without installing
# anything. The game then uses the system's own GTK 3 (ArmadaOS has it).
#
#   scripts/build-sysroot.sh OUTDIR [VERSION]
#
# Runs as root in an ubuntu:24.04 arm64 container. VERSION defaults to
# today's date (YYYY.MM.DD). Writes OUTDIR/skate3-arm64-sysroot-VERSION.tar.xz
# and OUTDIR/skate3-arm64-sysroot-VERSION.packages.txt (the packages and
# versions inside; their sources are on launchpad.net/ubuntu).
set -euo pipefail

out="$(mkdir -p "$1" && cd "$1" && pwd)"
version="${2:-$(date -u +%Y.%m.%d)}"
name="skate3-arm64-sysroot-$version"

if [ "$(dpkg --print-architecture)" != arm64 ]; then
    echo "error: run this in an arm64 Ubuntu 24.04 container" >&2
    exit 1
fi

packages=(
    libc6-dev linux-libc-dev libgcc-14-dev libstdc++-14-dev
    libx11-dev libx11-xcb-dev libxcb1-dev libxext-dev libxcursor-dev libxi-dev
    libxrandr-dev libxss-dev libxfixes-dev libxtst-dev libxkbcommon-dev
    libwayland-dev libwayland-bin wayland-protocols libdecor-0-dev
    libegl-dev libgl-dev libgles-dev libdrm-dev libgbm-dev
    libasound2-dev libpulse-dev libpipewire-0.3-dev libudev-dev libdbus-1-dev
    libgtk-3-dev
    pkgconf-bin libxml2
)
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q --no-install-recommends "${packages[@]}" python3 xz-utils

root="$(mktemp -d)/sysroot"
mkdir -p "$root/usr/lib" "$root/usr/bin" "$root/usr/share/doc"
cp -a /usr/include "$root/usr/"
cp -a /usr/lib/aarch64-linux-gnu "$root/usr/lib/"
mkdir -p "$root/usr/lib/gcc/aarch64-linux-gnu"
cp -a /usr/lib/gcc/aarch64-linux-gnu/14 "$root/usr/lib/gcc/aarch64-linux-gnu/"
cp -a /usr/lib/ld-linux-aarch64.so.1 "$root/usr/lib/"
for share in pkgconfig wayland wayland-protocols; do
    cp -a "/usr/share/$share" "$root/usr/share/"
done
cp -a /usr/bin/pkgconf /usr/bin/wayland-scanner "$root/usr/bin/"
ln -s usr/lib "$root/lib"
ln -s usr/bin "$root/bin"

# Only what a build links or runs: no drivers, interpreters or the LLVM that
# Mesa's drivers load.
lib="$root/usr/lib/aarch64-linux-gnu"
rm -rf "$lib"/dri "$lib"/gallium-pipe "$lib"/gconv "$lib"/perl* "$lib"/perl-base \
    "$lib"/python3* "$lib"/libpython3* "$lib"/libLLVM* "$lib"/libgallium* "$lib"/libvulkan_* \
    "$lib"/libz3*

# The licences of everything inside, and what it is.
dpkg-query -W -f '${binary:Package}\t${Version}\n' | sort > "$out/$name.packages.txt"
for doc in /usr/share/doc/*/copyright; do
    package="$(basename "$(dirname "$doc")")"
    mkdir -p "$root/usr/share/doc/$package"
    cp -L "$doc" "$root/usr/share/doc/$package/"
done
cp "$out/$name.packages.txt" "$root/usr/share/doc/PACKAGES.txt"

# Absolute links point at this container's /; point them inside the sysroot.
python3 - "$root" <<'EOF'
import os, sys
root = sys.argv[1]
for directory, folders, files in os.walk(root):
    for name in folders + files:
        path = os.path.join(directory, name)
        if os.path.islink(path) and os.readlink(path).startswith("/"):
            target = os.path.relpath(root + os.readlink(path), directory)
            os.unlink(path)
            os.symlink(target, path)
EOF

tar -C "$root" --sort=name --owner=0 --group=0 --numeric-owner --mtime=@0 -cf - . \
    | xz -T0 -6 > "$out/$name.tar.xz"
du -sh "$root" "$out/$name.tar.xz"
sha256sum "$out/$name.tar.xz"
