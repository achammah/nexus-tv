#!/bin/bash
# Network-cut test: plays through a local proxy, stops the proxy for 5 s mid-playback, and shows the player
# reconnecting by itself. Usage: scripts/netcut.sh live|film
set -uo pipefail
cd "$(dirname "$0")/.."
UDID=$(cat build/sim-udid); KIND=$1
case $KIND in
  live) PLAY=(-NXPlay live:2022589 -NXName "VTM 2") ;;
  film) PLAY=(-NXPlay film:1773307:mkv -NXName "The Sand Castle" -NXStart 600000) ;;
esac
python3 -I scripts/flaky_proxy.py 18888 & PROXY=$!
sleep 1
xcrun simctl terminate "$UDID" com.nexus.tv 2>&1 | grep -v "found nothing to terminate" | tail -1
T0=$(date +%s)
xcrun simctl launch "$UDID" com.nexus.tv -NXMetrics YES -NXStreamBase http://127.0.0.1:18888 "${PLAY[@]}" 2>&1 | tail -1
sleep 25; xcrun simctl io "$UDID" screenshot "shots/netcut-$KIND-1-playing.png" 2>&1 | tail -1
echo "cut at +$(( $(date +%s) - T0 )) s"
kill "$PROXY"; sleep 2
xcrun simctl io "$UDID" screenshot "shots/netcut-$KIND-2-cut.png" 2>&1 | tail -1
sleep ${CUT:-3}
python3 -I scripts/flaky_proxy.py 18888 & PROXY=$!
echo "network back at +$(( $(date +%s) - T0 )) s"
sleep 25; xcrun simctl io "$UDID" screenshot "shots/netcut-$KIND-3-after.png" 2>&1 | tail -1
kill "$PROXY"
DATA=$(xcrun simctl get_app_container "$UDID" com.nexus.tv data)
python3 - "$DATA/Library/Caches/metrics.log" "$T0" <<'PY'
import sys
t0 = float(sys.argv[2])
for l in open(sys.argv[1]):
    t, _, s = l.strip().partition(' ')
    if s.startswith('player'):
        print('+%5.1f s  %s' % (float(t) - t0, s.split(' +')[0]))
PY
