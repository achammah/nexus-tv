#!/bin/bash
# Speed run without XCUITest (UI tests turn on accessibility automation, which adds its own cost to every press):
# the remote is driven with real key events sent to the Simulator window (arrows = swipes, Return = select,
# Escape = Menu). Prints the same numbers as perf.sh.
set -uo pipefail
cd "$(dirname "$0")/.."
UDID=$(cat build/sim-udid)
APP="${APP:-build/dd/Build/Products/Release-appletvsimulator/Nexus TV.app}"
xcrun simctl install "$UDID" "$APP" 2>&1 | tail -1
xcrun simctl terminate "$UDID" com.nexus.tv 2>&1 | grep -v "found nothing" | tail -1
P=shots/perf-phases.txt; : > "$P"
stamp() { python3 -c "import time;print('%.3f $1' % time.time())" >> "$P"; }
key() { osascript -e "tell application \"System Events\" to key code $1" 2>&1 | head -1; }
keys() { for i in $(seq 1 "$2"); do key "$1"; sleep "${3:-0.3}"; done; }
L=123; R=124; D=125; U=126; ESC=53
xcrun simctl launch "$UDID" com.nexus.tv -NXMetrics YES -NXTab home -NXResetLayout YES $PERF_ARGS 2>&1 | tail -1
osascript -e 'tell application "Simulator" to activate' 2>&1 | head -1
sleep 15
key $D; sleep 1; key $D; sleep 1
stamp "home-focus start"
keys $R 20 0.25; key $D; keys $L 10 0.25; key $D; keys $R 10 0.25; key $D; keys $R 10 0.25
stamp "home-focus end"
sleep 2
# Live TV channel list: a fresh launch straight into the guide (the Home log is kept first)
DATA=$(xcrun simctl get_app_container "$UDID" com.nexus.tv data)
cp "$DATA/Library/Caches/metrics.log" build/metrics-home.log
xcrun simctl terminate "$UDID" com.nexus.tv 2>&1 | grep -v "found nothing" | tail -1
xcrun simctl launch "$UDID" com.nexus.tv -NXMetrics YES -NXTab live $PERF_ARGS 2>&1 | tail -1
sleep 12; key $D; sleep 0.5; key $D; sleep 0.5; key $R; sleep 2
stamp "guide-focus start"
keys $D 20 0.25
stamp "guide-focus end"
sleep 2
cp "$DATA/Library/Caches/metrics.log" build/metrics-guide.log
# tab switches: a fresh launch, focus starts on the Home tab of the menu; Right walks the tabs
xcrun simctl terminate "$UDID" com.nexus.tv 2>&1 | grep -v "found nothing" | tail -1
xcrun simctl launch "$UDID" com.nexus.tv -NXMetrics YES -NXTab home -NXResetLayout YES $PERF_ARGS 2>&1 | tail -1
sleep 14
for round in 1 2; do
  for t in live films series mylist search; do stamp "switch $round $t"; key $R; sleep 3; done
  keys $L 5 0.5; sleep 3
done
cat build/metrics-home.log build/metrics-guide.log "$DATA/Library/Caches/metrics.log" > build/metrics-all.log
python3 -I scripts/perf.py build/metrics-all.log "$P"
