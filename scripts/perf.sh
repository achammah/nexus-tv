#!/bin/bash
# Speed run on the simulator (Release build): prints launch, focus-move and tab-switch numbers.
set -uo pipefail
cd "$(dirname "$0")/.."
UDID=$(cat build/sim-udid)
mkdir -p shots/remote
TEST_RUNNER_NX_PERF_ARGS="${PERF_ARGS:-}" TEST_RUNNER_SHOTS_DIR="$PWD/shots/remote" xcodebuild test -project NexusTV.xcodeproj -scheme NexusTV -configuration Release \
  -destination "id=$UDID" -derivedDataPath build/dd -only-testing:NexusTVUITests/PerfTests > build/perf-raw.log 2>&1; grep -E "error:|Test Case .*(passed|failed)|crash|Crash" build/perf-raw.log | head
DATA=$(xcrun simctl get_app_container "$UDID" com.nexus.tv data)
python3 -I scripts/perf.py "$DATA/Library/Caches/metrics.log" shots/perf-phases.txt
