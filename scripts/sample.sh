#!/bin/bash
# CPU sampling of the app during the speed run's Home focus phase (macOS `sample` on the simulator process).
# Usage: scripts/sample.sh <label>  -> build/sample-<label>.txt (main thread call tree)
set -uo pipefail
cd "$(dirname "$0")/.."
UDID=$(cat build/sim-udid)
( PERF_ARGS="${PERF_ARGS:-}" scripts/perf.sh > "build/perf-$1.txt" 2>&1 ) &
RUN=$!
PID=""
for i in $(seq 1 240); do
  PID=$(xcrun simctl spawn "$UDID" launchctl list 2>&1 | awk '/UIKitApplication:com\.nexus\.tv\[/ {print $1}' | grep -E '^[0-9]+$' | head -1)
  [ -n "$PID" ] && break; sleep 0.5
done
echo "app pid ${PID:-none}"
sleep 17          # the test waits 15 s after launch, then two moves: the Home focus phase is running
sample "$PID" 20 -mayDie -file "build/sample-$1.txt" 2>&1 | tail -1
wait $RUN
grep -E "home-focus|guide-focus" "build/perf-$1.txt"
