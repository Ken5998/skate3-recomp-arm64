#!/usr/bin/env bash
# Builds Skate 3 (Skate 3 Recomp) for linux-arm64 from your own Skate 3
# (Xbox 360) disc image, start to finish: the toolchain, Skate 3 Recomp with
# this repository's patches, the game files from the disc, Title Update 3,
# the recompiled code, the game, and a ready folder to play from, added to
# Steam. Made for the handheld itself (ArmadaOS on the Retroid Pocket 6, or
# any aarch64 Linux). FS_ADD_TO_STEAM=0 leaves Steam alone.
#
#   scripts/build.sh ISO [DIR]
#
# ISO  your Skate 3 (Xbox 360) disc image, or - to keep the game files an
#      earlier build took from it (to update)
# DIR  where everything goes (default ~/.local/share/Skate3Recomp-arm64);
#      about 25 GB free is needed while building
#
# Title Update 3 (TU_12K2276_000000C000000.00000000000O3), which Skate 3
# Recomp is made for, is downloaded the way the game's own installer does
# (from xboxunity.net, the address in upstream.json); to use a copy you have,
# put it in DIR first or set S3_TITLE_UPDATE=FILE.
#
# Run it again after updating this repository: finished steps are skipped
# when nothing they depend on changed, and the game build recompiles only the
# files a change touches. Nothing made here may be published (it is built
# from your copy of the game).
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
[ $# -ge 1 ] && { [ "$1" = - ] || [ -f "$1" ]; } || { echo "usage: $0 ISO|- [DIR]" >&2; exit 2; }
case "$(uname -m)" in
    aarch64|arm64) ;;
    *) echo "error: build on the handheld (aarch64 Linux)" >&2; exit 1 ;;
esac
iso="$1"
[ "$iso" = - ] || iso="$(cd "$(dirname "$iso")" && pwd)/$(basename "$iso")"
dir="${2:-$HOME/.local/share/Skate3Recomp-arm64}"
mkdir -p "$dir"
dir="$(cd "$dir" && pwd)"
tc="$dir/toolchain"
work="$dir"
s3="$work/skate3recomp"
dist="$dir/game-dist"
data="$dist/game"
stamps="$dir/.stamps"
mkdir -p "$stamps" "$dist"

step() { printf '\n==> [%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
key() { cat "$@" | sha256sum | cut -d' ' -f1; }  # key FILE...: a hash of their contents
done_with() { [ -f "$stamps/$1" ] && [ "$(cat "$stamps/$1")" = "$2" ]; }
mark() { echo "$2" > "$stamps/$1"; }
field() {  # field KEY... : a value from upstream.json
    python3 -c 'import json, sys
v = json.load(open(sys.argv[1]))
for k in sys.argv[2:]: v = v[k]
print(v)' "$repo/upstream.json" "$@"
}

step "Toolchain"
"$repo/scripts/fetch-toolchain.sh" "$tc"
export PATH="$tc/bin:$PATH"

prepare_key="$(key "$repo/upstream.json" "$repo/scripts/prepare.sh" "$repo"/patches/*/*.patch)"
if done_with prepare "$prepare_key" && [ -d "$s3/.git" ]; then
    echo "Skate 3 Recomp already prepared - skipping."
else
    step "Skate 3 Recomp and its ReXGlue SDK sources"
    "$repo/scripts/prepare.sh" "$work"
    mark prepare "$prepare_key"
fi

# The whole disc, as the game's own installer would copy it, into game/
# beside the program: codegen reads the two executables from it, the game
# everything else.
main_xex="$data/default.xex"
webkit_xex="$data/data/webkit/EAWebkit.xex"
iso_key="$iso $( [ "$iso" = - ] || stat -c '%s %Y' "$iso")"
if [ -f "$main_xex" ] && { [ "$iso" = - ] || done_with extract "$iso_key"; }; then
    echo "Game files already taken from the disc - skipping."
elif [ "$iso" = - ]; then
    echo "error: no game files in $data yet: give your disc image instead of -" >&2
    exit 1
else
    step "Copying the game files from $iso (a few minutes)"
    # Saints Reborn's XDVDFS extractor, downloaded at the commit and hash in
    # upstream.json and built here.
    tools="$dir/tools"
    mkdir -p "$tools"
    src="$tools/xiso_extract.cpp"
    url="$(field xiso_extract url)"
    sum="$(field xiso_extract sha256)"
    if [ ! -f "$src" ] || [ "$(sha256sum "$src" | cut -d' ' -f1)" != "$sum" ]; then
        curl -fsSL --retry 3 -o "$src.part" "$url"
        [ "$(sha256sum "$src.part" | cut -d' ' -f1)" = "$sum" ] ||
            { echo "error: $url does not match its hash in upstream.json" >&2; exit 1; }
        mv "$src.part" "$src"
    fi
    clang=("$tc/llvm/bin/clang++" --target=aarch64-linux-gnu "--sysroot=$tc/sysroot"
           -fuse-ld=lld -static-libstdc++)
    [ ! -e "$tc/bin/ld.lld" ] || clang+=("--ld-path=$tc/bin/ld.lld")
    "${clang[@]}" -std=c++17 -O2 -o "$tools/xiso_extract" "$src"
    rm -rf "$data"
    "$tools/xiso_extract" "$iso" "$data" \
        --skip-name '$SystemUpdate' --skip-name layer1filler.bin --skip-name layer2filler.bin
    [ -f "$main_xex" ] || {
        echo "error: the disc image has no default.xex - is it an Xbox 360 game disc?" >&2; exit 1; }
    mark extract "$iso_key"
fi
[ -f "$webkit_xex" ] || { echo "error: $webkit_xex is missing: is this Skate 3 for Xbox 360?" >&2; exit 1; }

tu_name="$(field title_update name)"
tu="${S3_TITLE_UPDATE:-$dir/$tu_name}"
if [ ! -s "$tu" ]; then
    step "Downloading Title Update 3"
    curl -fL --retry 3 --connect-timeout 30 -o "$tu.part" "$(field title_update url)"
    mv "$tu.part" "$tu"
fi
tu="$(cd "$(dirname "$tu")" && pwd)/$(basename "$tu")"

game_key="$prepare_key $(key "$repo/toolchain.json" "$repo/scripts/build-game.sh" "$repo/scripts/common.sh")"
codegen_key="$game_key $(key "$main_xex" "$webkit_xex" "$tu")"
codegen=()
if done_with codegen "$codegen_key" && [ -f "$s3/generated/sources.cmake" ] && [ -f "$s3/generated/eawebkit/sources.cmake" ]; then
    echo "Recompiled code already generated - skipping that part."
else
    codegen=(--codegen)
fi
step "Building Skate 3 (an hour or more on a handheld)"
"$repo/scripts/build-game.sh" "${codegen[@]}" "$s3" "$tc" "$data" "$tu"
mark codegen "$codegen_key"

step "Putting the game together in $dist"
build="$s3/out/linux-arm64"
cp -f "$build/skate3" "$build/librexruntime.so" "$dist/"
# Title Update 3's patches, staged by the build the way the game's installer
# stages them.
mkdir -p "$data/data/webkit"
cp -f "$build/game/default.xexp" "$data/default.xexp"
cp -f "$build/game/data/webkit/EAWebkit.xexp" "$data/data/webkit/EAWebkit.xexp"
install -m 755 "$repo/config/skate3.sh" "$dist/skate3.sh"
# Your settings stay; the handheld defaults go in only the first time.
[ -f "$dist/skate3.toml" ] || cp "$repo/config/skate3.toml" "$dist/skate3.toml"

steam=no
if [ "${FS_ADD_TO_STEAM:-1}" = 1 ]; then
    step "Adding Skate 3 to Steam"
    if python3 -I "$repo/scripts/add-to-steam.py" "$dist"; then
        steam=yes
    else
        echo "Warning: Skate 3 was not added to Steam; scripts/add-to-steam.py tries again."
    fi
fi

echo
echo "Done at $(date +%H:%M:%S)! Skate 3 is in $dist."
if [ "$steam" = yes ]; then
    echo "Play it from Steam (\"Skate 3\" in the library): the handheld's controls reach it only from there."
else
    echo "Play it from Steam (scripts/add-to-steam.py adds it) so the controls work,"
    echo "or run $dist/skate3.sh from a terminal."
fi
