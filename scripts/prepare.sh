#!/usr/bin/env bash
# Checks out Skate 3 Recomp at the commit in upstream.json (or REF) with its
# submodules (its fork of the ReXGlue SDK and the SDK's thirdparty), then
# applies this repository's patches: patches/game/*.patch to Skate 3 Recomp,
# patches/sdk/*.patch to third_party/rexglue-sdk and patches/imgui/*.patch to
# its thirdparty/imgui.
#
#   scripts/prepare.sh WORKDIR [REF]
#
# WORKDIR/skate3recomp   the patched tree; generated/ and out/ are left alone
#
# Run again, it checks out and patches again; files that end up the same keep
# their times (scripts/keep-times.py), so a later build recompiles only what
# changed. No game files are involved.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mkdir -p "$1" && cd "$1" && pwd)"

field() {
    python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' \
        "$repo/upstream.json" "$1"
}
ref="${2:-$(field commit)}"
s3="$work/skate3recomp"
sdk="$s3/third_party/rexglue-sdk"
times="$work/.prepare-times.json"
python3 "$repo/scripts/keep-times.py" save "$times" "$s3"

if [ ! -d "$s3/.git" ]; then
    git clone -q -c core.autocrlf=false "$(field repository)" "$s3"
fi
git -C "$s3" fetch -q origin "$ref" 2>/dev/null || git -C "$s3" fetch -q origin
git -C "$s3" -c advice.detachedHead=false checkout -q --force "$ref"
# Files an earlier patch added; checkout --force leaves them. Generated code
# and build folders stay.
git -C "$s3" clean -fdq -e generated -e out
git -C "$s3" submodule sync -q --recursive
git -C "$s3" submodule update -q --init --force third_party/rexglue-sdk
git -C "$sdk" clean -fdq -e out
# The SDK fork records an imgui commit with its own changes that was never
# pushed (only on the author's machine): imgui comes separately, at that
# commit if GitHub ever has it, else at the last public commit the fork used
# (upstream.json "imgui"); patches/sdk make up for what is missing.
git -C "$sdk" -c submodule.thirdparty/imgui.update=none submodule update -q --init --recursive --force --depth 1 ||
    git -C "$sdk" -c submodule.thirdparty/imgui.update=none submodule update -q --init --recursive --force
imgui="$sdk/thirdparty/imgui"
imgui_recorded="$(git -C "$sdk" ls-tree HEAD thirdparty/imgui | cut -d' ' -f3 | cut -f1)"
imgui_public="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["imgui"]["commit"])' "$repo/upstream.json")"
[ -e "$imgui/.git" ] || git -C "$sdk" submodule update -q --init --checkout --force --depth 1 thirdparty/imgui 2>/dev/null || true
if [ ! -e "$imgui/.git" ]; then
    rm -rf "$imgui"
    git init -q "$imgui"
    git -C "$imgui" remote add origin "$(git -C "$sdk" config -f .gitmodules submodule.thirdparty/imgui.url)"
fi
if [ "$(git -C "$imgui" rev-parse -q --verify HEAD 2>/dev/null)" != "$imgui_recorded" ]; then
    if git -C "$imgui" fetch -q --depth 1 origin "$imgui_recorded" 2>/dev/null; then
        imgui_use="$imgui_recorded"
    else
        imgui_use="$imgui_public"
        git -C "$imgui" fetch -q --depth 1 origin "$imgui_use"
    fi
    git -C "$imgui" -c advice.detachedHead=false checkout -q --force "$imgui_use"
fi
git -C "$imgui" clean -fdq
echo "Skate 3 Recomp $(git -C "$s3" rev-parse --short HEAD), SDK $(git -C "$sdk" rev-parse --short HEAD), imgui $(git -C "$imgui" rev-parse --short HEAD)"

for patch in "$repo"/patches/game/*.patch; do
    [ -e "$patch" ] || continue
    git -C "$s3" apply --whitespace=nowarn "$patch"
    echo "Applied ${patch#"$repo"/}"
done
for patch in "$repo"/patches/imgui/*.patch; do
    [ -e "$patch" ] || continue
    git -C "$imgui" apply --whitespace=nowarn "$patch"
    echo "Applied ${patch#"$repo"/}"
done
for patch in "$repo"/patches/sdk/*.patch; do
    [ -e "$patch" ] || continue
    git -C "$sdk" apply --whitespace=nowarn "$patch"
    echo "Applied ${patch#"$repo"/}"
done

python3 "$repo/scripts/keep-times.py" restore "$times"
