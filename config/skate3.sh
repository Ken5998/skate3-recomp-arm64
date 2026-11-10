#!/usr/bin/env bash
# Starts Skate 3 (Skate 3 Recomp, linux-arm64). Installed beside the game as
# skate3.sh by scripts/build.sh; Steam starts this.
#
# The game files taken from your disc are in game/ beside it, settings in
# skate3.toml (first-start defaults) and the game's own settings file, saves
# in ~/.config/skate3 or wherever the game reports in Logs/skate3.log.
# F5 switches between the native renderer and the emulated Xbox 360 GPU.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
cd "$here"
mkdir -p Logs

[ -f "$here/game/default.xex" ] ||
    { echo "error: no game files in $here/game: run the launcher's Build again with your disc image" >&2; exit 1; }

export LD_LIBRARY_PATH="$here${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$here/skate3" --log_file="$here/Logs/skate3.log" "$@"
