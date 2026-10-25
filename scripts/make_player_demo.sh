#!/bin/bash
# Test videos for Tests/tvOSUITests/PlayerRedesignTests.swift (no provider stream is ever opened by these tests):
#   demo.mkv   5 min, 6 audio tracks (English 5.1, English description, German 5.1, German stereo, Japanese original, one untagged)
#              and 5 subtitle tracks (English, SDH, Forced, French, Dutch)
#   demo90.mkv 90 s, one audio track (the episode chain and "Still watching?" tests)
# Usage: scripts/make_player_demo.sh <output folder>; then run the tests with
#   TEST_RUNNER_NX_LOCAL=<folder>/demo.mkv TEST_RUNNER_NX_LOCAL90=<folder>/demo90.mkv TEST_RUNNER_SHOTS_DIR=<shots folder> xcodebuild test ...
set -euo pipefail
OUT="${1:?output folder}"; mkdir -p "$OUT"; cd "$OUT"
python3 - <<'PY'
def ts(s): return f"{s//3600:02d}:{(s%3600)//60:02d}:{s%60:02d},000"
for name, txt, step in [("eng","Hello there.",5),("sdh","[door closes] Hello there.",5),("forced","(in Gaelic)",40),("fre","Bonjour.",5),("dut","Hallo.",5)]:
    out = [f"{i+1}\n{ts(t)} --> {ts(t+3).replace(',000',',500')}\n{txt}\n" for i, t in enumerate(range(2, 200, step))]
    open(f"{name}.srt", "w").write("\n".join(out))
PY
ffmpeg -hide_banner -loglevel error -y -f lavfi -i "testsrc2=size=1280x720:rate=25:duration=300" \
  -f lavfi -i "sine=frequency=220:duration=300" -f lavfi -i "sine=frequency=262:duration=300" -f lavfi -i "sine=frequency=294:duration=300" \
  -f lavfi -i "sine=frequency=330:duration=300" -f lavfi -i "sine=frequency=349:duration=300" -f lavfi -i "sine=frequency=392:duration=300" \
  -i eng.srt -i sdh.srt -i forced.srt -i fre.srt -i dut.srt \
  -map 0:v -map 1:a -map 2:a -map 3:a -map 4:a -map 5:a -map 6:a -map 7 -map 8 -map 9 -map 10 -map 11 \
  -c:v libx264 -preset ultrafast -crf 32 -pix_fmt yuv420p -g 50 \
  -c:a:0 ac3 -ac:a:0 6 -metadata:s:a:0 language=eng \
  -c:a:1 aac -ac:a:1 2 -metadata:s:a:1 language=eng -metadata:s:a:1 title="Audio Description" \
  -c:a:2 ac3 -ac:a:2 6 -metadata:s:a:2 language=ger -c:a:3 aac -ac:a:3 2 -metadata:s:a:3 language=ger \
  -c:a:4 aac -ac:a:4 2 -metadata:s:a:4 language=jpn -metadata:s:a:4 title="Original" -c:a:5 aac -ac:a:5 2 \
  -c:s srt -metadata:s:s:0 language=eng -metadata:s:s:1 language=eng -metadata:s:s:1 title="SDH" \
  -metadata:s:s:2 language=eng -metadata:s:s:2 title="Forced" -metadata:s:s:3 language=fre -metadata:s:s:4 language=dut demo.mkv
ffmpeg -hide_banner -loglevel error -y -f lavfi -i "testsrc2=size=640x360:rate=25:duration=90" -f lavfi -i "sine=frequency=330:duration=90" \
  -c:v libx264 -preset ultrafast -crf 35 -pix_fmt yuv420p -g 50 -c:a aac -ac 2 demo90.mkv
echo "wrote $OUT/demo.mkv and $OUT/demo90.mkv"
