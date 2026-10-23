#!/bin/bash
# Build for the tvOS simulator, (re)install, launch with optional launch arguments, screenshot after N seconds.
# Usage: scripts/sim.sh <shot-name|-> <wait-seconds> [launch args, e.g. -NXTab live]
set -euo pipefail
cd "$(dirname "$0")/.."
UDID=$(cat build/sim-udid)
NAME=$1; WAIT=$2; shift 2
if [ "${NOBUILD:-}" != 1 ]; then
  xcodebuild -project NexusTV.xcodeproj -scheme NexusTV -destination "id=$UDID" -derivedDataPath build/dd build -quiet 2>&1 | grep -E "error:" && exit 1
  xcrun simctl install "$UDID" "build/dd/Build/Products/Debug-appletvsimulator/Nexus TV.app"
fi
xcrun simctl terminate "$UDID" com.nexus.tv 2>&1 | grep -v "found nothing to terminate" | tail -1
xcrun simctl launch "$UDID" com.nexus.tv "$@" 2>&1 | tail -1
sleep "$WAIT"
[ "$NAME" = "-" ] || xcrun simctl io "$UDID" screenshot "shots/$NAME.png" 2>&1 | tail -1
