#!/bin/bash
# Runs the remote-driven journey on the simulator; screenshots land in shots/remote/.
set -uo pipefail
cd "$(dirname "$0")/.."
UDID=$(cat build/sim-udid)
mkdir -p shots/remote
# The account journeys type a real login read from NXTV_ACCOUNT_FILE (3 lines: server, username, password; keep it
# outside the repo). Nothing is printed, the log is masked, and the result bundle is deleted after.
: "${NXTV_ACCOUNT_FILE:?set NXTV_ACCOUNT_FILE to a 3-line file: server, username, password}"
{ read -r S; read -r U; read -r P; } < "$NXTV_ACCOUNT_FILE"
export TEST_RUNNER_NX_SERVER="$S" TEST_RUNNER_NX_USER="$U" TEST_RUNNER_NX_PASS="$P"
TEST_RUNNER_SHOTS_DIR="$PWD/shots/remote" xcodebuild test -project NexusTV.xcodeproj -scheme NexusTV -destination "id=$UDID" \
  -derivedDataPath build/dd -resultBundlePath build/uitest.xcresult "$@" > build/uitest-raw.log 2>&1
python3 -I scripts/safe_log.py build/uitest-raw.log
rm -rf build/uitest.xcresult build/uitest-raw.log
