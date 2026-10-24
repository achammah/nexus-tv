#!/bin/bash
# Runs the Mac app's UI journeys (XCUITest, mouse and keyboard); screenshots land in shots/mac/ (git-ignored).
# The login comes from NXTV_ACCOUNT_FILE (3 lines: server, username, password; outside the repo), never printed;
# the log is masked and the result bundle deleted after. Optional: OSUB_ACCOUNT_FILE for online subtitles.
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p shots/mac build
: "${NXTV_ACCOUNT_FILE:?set NXTV_ACCOUNT_FILE to a 3-line file: server, username, password}"
{ read -r S; read -r U; read -r P; } < "$NXTV_ACCOUNT_FILE"
export TEST_RUNNER_NX_SERVER="$S" TEST_RUNNER_NX_USER="$U" TEST_RUNNER_NX_PASS="$P"
rm -rf build/mactest.xcresult
TEST_RUNNER_SHOTS_DIR="$PWD/shots/mac" xcodebuild test -project NexusTV.xcodeproj -scheme NexusTVMac -destination 'platform=macOS' \
  -derivedDataPath build/ddm -resultBundlePath build/mactest.xcresult "$@" > build/mactest-raw.log 2>&1
EC=$?
# the runner is sandboxed: its screenshots are in its container's temporary folder
SRC="$HOME/Library/Containers/com.nexus.tv.mac.uitests.xctrunner/Data/tmp/nxshots"
if [ -d "$SRC" ]; then cp "$SRC"/*.png shots/mac/ && rm -rf "$SRC"; fi
python3 -I scripts/safe_log.py build/mactest-raw.log
rm -rf build/mactest.xcresult build/mactest-raw.log
exit $EC
