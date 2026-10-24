#!/bin/bash
# Package the app from a clean copy (no git, no cache, no tools), sign with the 'frame' profile, install, open it.
#   tools/package.sh               the Frame, login from ~/.nexus-secrets/tvapp-iptv.key
#   tools/package.sh tv2 <ip>      the second TV, login from ~/.nexus-secrets/tvapp-iptv-tv2.key
set -o pipefail
export PATH="$HOME/tizen-studio/tools:$HOME/tizen-studio/tools/ide/bin:$PATH"
APP="$(cd "$(dirname "$0")/.." && pwd)"; STAGE="$APP/.cache/stage"
if [ "$1" = "tv2" ]; then TV=${2:?usage: package.sh tv2 <ip>}; KEY=~/.nexus-secrets/tvapp-iptv-tv2.key; else TV=${TV:-<your-frame-ip>}; KEY=; fi
SERIAL=$TV:26101
rm -rf "$STAGE" && mkdir -p "$STAGE" || exit 1
rsync -a --exclude .git --exclude .cache --exclude tools --exclude '*.wgt' --exclude .gitignore "$APP/" "$STAGE/" || exit 1
# Another TV's login goes only into the staged copy, never the work folder.
if [ -n "$KEY" ]; then python3 -c "import json,sys; b,u,p=[l.strip() for l in open(sys.argv[1]) if l.strip()][:3]; open(sys.argv[2],'w').write('window.IPTV=%s;\n' % json.dumps({'base': b.rstrip('/'), 'user': u, 'pass': p}))" "$KEY" "$STAGE/data/config.js" && grep -h "window.OSUB" "$APP/data/config.js" >> "$STAGE/data/config.js"; [ -s "$STAGE/data/config.js" ] || exit 1; fi
# DIAG=1: add the temporary reporter that posts player events to this Mac (tools/diag/sink.py listens).
if [ "$DIAG" = "1" ]; then MAC=$(ipconfig getifaddr en0); sed "s/__MAC__/$MAC/" "$APP/tools/diag/diag.js" > "$STAGE/js/diag.js" && sed -i '' 's#<script src="js/util.js"></script>#<script src="js/diag.js"></script><script src="js/util.js"></script>#' "$STAGE/index.html" && grep -q diag.js "$STAGE/index.html" || { echo "diag inject failed"; exit 1; }; fi
cd "$STAGE" && tizen package -t wgt -s frame -- . 2>&1 | grep -iE "rror|Location" ; ls ./*.wgt >/dev/null 2>&1 || { echo "package failed"; exit 1; }
mv ./*.wgt "$APP/.cache/TVapp.wgt"
sdb connect $TV 2>&1 | tail -1
TARGET=$(sdb devices 2>&1 | grep "$SERIAL" | awk '{print $3}'); [ -n "$TARGET" ] || { echo "TV not connected"; exit 1; }
tizen install -n "$APP/.cache/TVapp.wgt" -t $TARGET 2>&1 | grep -E "successfully|rror" || exit 1
sdb -s $SERIAL shell 0 was_execute wAKjt4yhqx.TVapp 2>&1 | grep -o "launch start\|resumed"
