#!/bin/bash
# Time Profiler over the speed run: starts the run, attaches xctrace to the app for 75 s, prints main-thread load.
set -uo pipefail
cd "$(dirname "$0")/.."
UDID=$(cat build/sim-udid); OUT=build/tp-$1.trace
rm -rf "$OUT"
( TEST_RUNNER_SHOTS_DIR="$PWD/shots/remote" xcodebuild test -project NexusTV.xcodeproj -scheme NexusTV -configuration Release \
    -destination "id=$UDID" -derivedDataPath build/dd -only-testing:NexusTVUITests/PerfTests > build/perf-run-$1.log 2>&1 ) &
for i in $(seq 1 180); do xcrun simctl spawn "$UDID" launchctl list 2>&1 | grep -q "com.nexus.tv" && break; sleep 1; done
sleep 4
xcrun xctrace record --template 'Time Profiler' --device "$UDID" --attach 'Nexus TV' --time-limit 70s --output "$OUT" > build/xctrace-$1.log 2>&1 &
XT=$!
sleep 85
kill -INT $XT 2>&1; sleep 8; kill -TERM $XT 2>&1
wait
grep -E "Test Case .*(passed|failed)" build/perf-run-$1.log
xcrun xctrace export --input "$OUT" --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' > build/tp-$1.xml 2>&1
python3 -I scripts/tp_summary.py build/tp-$1.xml
DATA=$(xcrun simctl get_app_container "$UDID" com.nexus.tv data)
python3 -I scripts/perf.py "$DATA/Library/Caches/metrics.log" shots/perf-phases.txt
