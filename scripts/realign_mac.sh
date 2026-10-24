#!/bin/bash
# Live realignment on the Mac with no mouse or keyboard: plays a film muted, picks the first online subtitle of a
# language through a launch hook, starts it 6 s off, and prints what the app found; then the true offset of the same
# file over the whole film (scripts/realign_check.py). Needs NXTV_ACCOUNT_FILE and OSUB_ACCOUNT_FILE (3-line files).
# Usage: scripts/realign_mac.sh [film id] [language]   (default: 2163590 fr, Spider-Man Brand New Day)
set -uo pipefail
cd "$(dirname "$0")/.."
FILM=${1:-2163590}; LANG_=${2:-fr}
APP="build/ddm/Build/Products/Debug/Nexus TV.app"; BIN="$APP/Contents/MacOS/Nexus TV"
LOG=~/Library/Caches/com.nexus.tv.mac/metrics.log
open -g -n --env "NXTV_SEED_ACCOUNT_FILE=${NXTV_ACCOUNT_FILE:?}" --env "NXTV_SEED_OSUB_FILE=${OSUB_ACCOUNT_FILE:?}" "$APP" --args \
  -NXWindowSize 1440x900 -ApplePersistenceIgnoreState YES -NXMetrics YES -NXMute YES -NXPlay "film:$FILM:mkv" -NXName "Realign check" \
  -NXStart 900000 -NXSubDelayStart 6000 -NXPickOnline "$LANG_"
sleep 120
grep -E "player.align|player.osub added" "$LOG" | cut -d' ' -f2-
for p in $(pgrep -f "$BIN"); do kill "$p"; done
FID=$(grep -o "player.align file=[0-9]*" "$LOG" | head -1 | cut -d= -f2)
SRT=$(getconf DARWIN_USER_TEMP_DIR)osub-$FID.srt
[ -f "$SRT" ] && python3 -I scripts/realign_check.py "$FILM" "$SRT"
