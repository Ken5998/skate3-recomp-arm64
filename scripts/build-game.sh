#!/usr/bin/env bash
# Builds Skate 3 Recomp for linux-arm64 with its fork of the ReXGlue SDK as
# part of the same build, as upstream does: natively on aarch64, or
# cross-compiled on x86-64 (CI, with placeholder-codegen.py's stand-in).
#
#   scripts/build-game.sh [--codegen] SKATE3 TOOLCHAIN [GAME [TU]]
#
# SKATE3     the tree prepare.sh made
# TOOLCHAIN  fetch-toolchain.sh's folder
# GAME       the game files taken from the disc (default.xex and
#            data/webkit/EAWebkit.xex at least)
# --codegen  generate the recompiled code from GAME first (rexglue codegen,
#            aarch64 only); without it SKATE3/generated must hold it already
# TU         Title Update 3 (TU_12K2276_000000C000000.00000000000O3), as
#            upstream's release builds use
#
# The program, librexruntime.so and (with TU) game/default.xexp and
# game/data/webkit/EAWebkit.xexp end up in SKATE3/out/linux-arm64.
#
# Parallel jobs: FS_JOBS, else one per logical CPU but at most one per 2 GB of
# memory (the recompiled files are huge).
set -euo pipefail

codegen=0
[ "${1:-}" != --codegen ] || { codegen=1; shift; }
repo="$(cd "$(dirname "$0")/.." && pwd)"
s3="$(cd "$1" && pwd)"
export FS_ARM64_TOOLCHAIN="$(cd "$2" && pwd)"
game="${3:-}"
tu="${4:-}"
build="$s3/out/linux-arm64"
llvm="$FS_ARM64_TOOLCHAIN/llvm/bin"
export PATH="$FS_ARM64_TOOLCHAIN/bin:$PATH"
. "$repo/scripts/common.sh"
jobs="$(build_jobs)"
echo "Building with $jobs parallel jobs ($(nproc) CPU threads)"

SOURCE_DATE_EPOCH="$(git -C "$s3" log -1 --format=%ct 2>/dev/null || echo 0)"
export SOURCE_DATE_EPOCH
configure() {
    cmake -S "$s3" -B "$build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
        "-DCMAKE_TOOLCHAIN_FILE=$repo/cmake/toolchains/linux-arm64.cmake" \
        "-DCMAKE_C_COMPILER=$llvm/clang" "-DCMAKE_CXX_COMPILER=$llvm/clang++" \
        "-DCMAKE_C_FLAGS=$FS_ARCH_FLAGS" "-DCMAKE_CXX_FLAGS=$FS_ARCH_FLAGS" \
        "-DREXSDK_DIR=$s3/third_party/rexglue-sdk" \
        ${game:+"-DSKATE3_GAME_DATA_ROOT=$game"} \
        "-DSKATE3_TITLE_UPDATE_PACKAGE=$tu" \
        -DREXGLUE_USE_VULKAN=ON -DREXGLUE_ENABLE_TRACY=OFF -DSDL_HIDAPI_LIBUSB=OFF
}

if [ "$codegen" = 1 ]; then
    [ -n "$game" ] || { echo "error: --codegen needs GAME" >&2; exit 2; }
    configure
    echo "Recompiling the game (PowerPC to C++)"
    cmake --build "$build" --target generate-all --parallel "$jobs"
fi
[ -f "$s3/generated/sources.cmake" ] && [ -f "$s3/generated/eawebkit/sources.cmake" ] ||
    { echo "error: no generated code in $s3/generated" >&2; exit 1; }
# Again, so CMake sees the generated source lists.
configure
cmake --build "$build" --target skate3 --parallel "$jobs"

check_aarch64 "$build/skate3"
check_aarch64 "$build/librexruntime.so"
