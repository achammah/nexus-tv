#!/bin/bash
# The opening check: frames 0 3 6 9 12 15 18 21 24 30 40 55 captured from the simulator (-NXOpeningFrame N holds
# frame N) under the same frames of the reference render. Output: shots/opening/strip.png (+ each frame).
set -uo pipefail
cd "$(dirname "$0")/.."
REF=${OPENING_REF:-$HOME/nexus/nexus-organisation/work/frame-tv/logo/final/opening.mp4}
UDID=$(cat build/sim-udid); BID=com.nexus.tv
mkdir -p shots/opening
xcrun simctl install "$UDID" "build/dd/Build/Products/Debug-appletvsimulator/Nexus TV.app" || exit 1
for f in 0 3 6 9 12 15 18 21 24 30 40 55; do
  xcrun simctl terminate "$UDID" "$BID" 2>&1 | grep -v "found nothing" | head -1
  xcrun simctl launch "$UDID" "$BID" -NXOpeningFrame $f > /dev/null || exit 1
  sleep 4
  xcrun simctl io "$UDID" screenshot "shots/opening/sim-$f.png" 2>&1 | grep -iv -e "wrote" -e "detected file" -e "no display" | head -2
  ffmpeg -v error -y -i "$REF" -vf "select=eq(n\,$f)" -frames:v 1 "shots/opening/ref-$f.png" || exit 1
done
xcrun simctl terminate "$UDID" "$BID"
python3 -I - shots/opening <<'PY'
import sys
from PIL import Image, ImageDraw
d0 = sys.argv[1]; F = [0, 3, 6, 9, 12, 15, 18, 21, 24, 30, 40, 55]; W, H = 320, 180
out = Image.new('RGB', (W * 6, (2 * H + 24) * 2), (30, 30, 30)); d = ImageDraw.Draw(out)
for i, f in enumerate(F):
    c, r = i % 6, i // 6; y = r * (2 * H + 24)
    out.paste(Image.open(f'{d0}/ref-{f}.png').convert('RGB').resize((W, H)), (c * W, y + 24))
    out.paste(Image.open(f'{d0}/sim-{f}.png').convert('RGB').resize((W, H)), (c * W, y + 24 + H))
    d.text((c * W + 6, y + 5), f'frame {f}' + ('  (top: opening.mp4 · bottom: Apple TV simulator)' if c == 0 else ''), fill=(255, 255, 255))
out.save(f'{d0}/strip.png'); print('strip', out.size)
PY
