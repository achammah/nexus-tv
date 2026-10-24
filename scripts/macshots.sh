#!/bin/bash
# Screenshots of the Mac app at 1440 x 900, each from the app's own window only (screencapture -l: no other app,
# no desktop). Uses the account already in the Keychain (run scripts/mactest.sh first). Output: shots/mac/*.png
set -uo pipefail
cd "$(dirname "$0")/.."
APP="build/ddm/Build/Products/Debug/Nexus TV.app"
BIN="$APP/Contents/MacOS/Nexus TV"
mkdir -p shots/mac build/macshots
swiftc -O -o build/macshots/mac_window scripts/mac_window.swift 2>&1 | grep -v "^$" | head -3
shot() {   # name seconds title-filter args...
  local name=$1 wait=$2 title=$3; shift 3
  open -g -n --env "NXTV_SEED_ACCOUNT_FILE=${NXTV_ACCOUNT_FILE:-}" "$APP" --args -NXWindowSize 1440x900 -ApplePersistenceIgnoreState YES "$@"
  sleep "$wait"
  local pid; pid=$(pgrep -nf "$BIN")
  local win; win=$(build/macshots/mac_window "$pid" "$title")
  if [ -n "$win" ]; then screencapture -x -o -l "$win" "shots/mac/$name.png" && echo "$name"; else echo "$name: no window"; fi
  for p in $(pgrep -f "$BIN"); do kill "$p"; done; sleep 3      # every copy of this debug build (its full path)
}
if [ -z "${ONLY_END:-}" ]; then
shot mac-home 25 "Nexus TV"
shot mac-live-belgium 25 "Nexus TV" -NXPage live:BE
shot mac-films 25 "Nexus TV" -NXPage films
shot mac-series 25 "Nexus TV" -NXPage series
shot mac-film-page 20 "Nexus TV" -NXOpen "film:1773307:The Sand Castle"
shot mac-search 60 "Nexus TV" -NXSearch rtl
shot mac-player-film 30 "Nexus TV" -NXPlay film:1773307:mkv -NXName "The Sand Castle" -NXStart 600000 -NXHudStay YES
shot mac-account 15 "Nexus TV" -NXPage account
shot mac-settings 15 "Nexus TV" -NXPage settings
shot mac-player 30 "Nexus TV" -NXPlay episode:1928870:mkv -NXName "House Of Guinness · S1 E1" -NXSeries "45370:House Of Guinness" -NXStart 600000 -NXHudStay YES -NXResetUser YES
fi
if [ -z "${ONLY_FIRST:-}" ]; then
# after the player has saved a resume point for episode 1: its progress bar shows on the series page
shot mac-series-page 20 "Nexus TV" -NXOpen "series:45370:House Of Guinness"
[ -n "${ONLY_FIRST:-}" ] || shot mac-next-episode-card 38 "Nexus TV" -NXPlay episode:1928870:mkv -NXName "House Of Guinness · S1 E1" -NXSeries "45370:House Of Guinness" -NXStart 3100000
fi
# last: a new install, the account sheet over the empty window (the window and its sheet captured apart, then
# put together: no other app can show). The Keychain account is forgotten; the next run signs in again.
swiftc -O -o build/macshots/mac_windows scripts/mac_windows.swift 2>&1 | grep -v "^$" | head -3
open -g -n "$APP" --args -NXWindowSize 1440x900 -ApplePersistenceIgnoreState YES -NXResetAccounts YES
sleep 14
pid=$(pgrep -nf "$BIN")
build/macshots/mac_windows "$pid" > build/macshots/windows.txt
python3 -I - build/macshots/windows.txt shots/mac/mac-first-launch.png <<'PY'
import subprocess, sys
from PIL import Image
rows = [l.split(None, 5) for l in open(sys.argv[1]) if l.strip()]
rows = [(r[0], float(r[1]), float(r[2]), float(r[3]), float(r[4])) for r in rows if float(r[4]) > 100]
rows.sort(key=lambda r: -r[3] * r[4])                  # the main window first, then the sheet
base = None
for i, (wid, x, y, w, h) in enumerate(rows[:2]):
    f = 'build/macshots/w%d.png' % i
    subprocess.run(['screencapture', '-x', '-o', '-l', wid, f], check=True)
    im = Image.open(f).convert('RGBA')
    if base is None:
        base, bx, by, scale = im, x, y, im.width / w
    else:
        base.alpha_composite(im, (int((x - bx) * scale), int((y - by) * scale)))
base.convert('RGB').save(sys.argv[2])
print('mac-first-launch')
PY
for p in $(pgrep -f "$BIN"); do kill "$p"; done
