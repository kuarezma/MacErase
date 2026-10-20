#!/bin/zsh
# Screenshot one section of the built app: Scripts/shot.sh <overview|apps|clean|large|startup> <out.png> [AppName]
set -euo pipefail
cd "$(dirname "$0")/.."
pkill -x MacErase 2>/dev/null || true; sleep 2
ARGS=(--env MACERASE_SECTION="$1"); [ -n "${3:-}" ] && ARGS+=(--env MACERASE_SELECT="$3")
[ -n "${SHOT_SCAN:-}" ] && ARGS+=(--env MACERASE_AUTOSCAN=1)
LANG_ARGS=(); [ -n "${SHOT_LANG:-}" ] && LANG_ARGS=(--args -AppleLanguages "($SHOT_LANG)")
open -n "${ARGS[@]}" build/MacErase.app "${LANG_ARGS[@]}"
sleep "${SHOT_WAIT:-6}"
ID=$(swift Scripts/windowid.swift)
screencapture -x -o -l"$ID" "$2"
