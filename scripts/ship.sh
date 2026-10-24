#!/bin/bash
# Archive, scan and upload one Apple TV commit to TestFlight from a clean worktree. Usage: scripts/ship.sh <commit> <tag>
# Needs (outside git): Config/Signing.xcconfig, Config/ExportOptions.plist (the export options: team, method),
# ~/.nexus-secrets/apple-id.txt and apple-asp.txt (Apple ID and app-specific password, read at run time, never printed).
set -euo pipefail
C=$1; T=$2
REPO=$(cd "$(dirname "$0")/.." && pwd)
SP=$REPO/build/ship; mkdir -p "$SP"
W=$SP/clean-$T; S=$SP; cp "$REPO/Config/ExportOptions.plist" "$S/export.plist"
git -C "$REPO" worktree add --detach "$W" "$C" 2>&1 | tail -1
ln -s "$REPO/Vendor" "$W/Vendor"; cp "$REPO/Config/Signing.xcconfig" "$W/Config/"
[ -d "$S/NexusTV.xcarchive" ] && mv "$S/NexusTV.xcarchive" "$S/NexusTV-before-$T.xcarchive"
[ -d "$S/export" ] && mv "$S/export" "$S/export-before-$T"
xcodebuild -project "$W/NexusTV.xcodeproj" -scheme NexusTV -configuration Release -destination generic/platform=tvOS -derivedDataPath "$S/dd-$T" -archivePath "$S/NexusTV.xcarchive" CODE_SIGNING_ALLOWED=NO archive > "$S/archive-$T.log" 2>&1
echo "archive ok, build $(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleVersion' "$S/NexusTV.xcarchive/Info.plist")"
xcodebuild -exportArchive -archivePath "$S/NexusTV.xcarchive" -exportOptionsPlist "$S/export.plist" -exportPath "$S/export" -allowProvisioningUpdates > "$S/export-$T.log" 2>&1 || { grep -E "error" "$S/export-$T.log" | head -3; exit 1; }
echo "export ok"
mkdir -p "$S/ipa-$T" && (cd "$S/ipa-$T" && unzip -q -o "$S/export/Nexus TV.ipa")
python3 - "$S/ipa-$T" <<'EOF'
import os,re,sys
vals=[]
for f in ["tvapp-iptv.key","tvapp-iptv.key.expired","tvapp-iptv-tv2.key","opensubtitles.key"]:
    p=os.path.expanduser("~/.nexus-secrets/"+f)
    if not os.path.exists(p): continue
    for v in open(p).read().split():
        if "://" in v: v=re.sub(r"^\w+://","",v).split("/")[0].split(":")[0]
        if len(v)>=6: vals.append(v.encode())
h=0
for r,_,fs in os.walk(sys.argv[1]):
    for f in fs: b=open(os.path.join(r,f),"rb").read(); h+=sum(v in b for v in vals)
print("ipa secret hits",h); sys.exit(1 if h else 0)
EOF
ASC_ASP=$(cat ~/.nexus-secrets/apple-asp.txt) xcrun altool --upload-app -f "$S/export/Nexus TV.ipa" -t tvos -u "$(cat ~/.nexus-secrets/apple-id.txt)" -p @env:ASC_ASP > "$S/upload-$T.log" 2>&1 || { grep ERROR "$S/upload-$T.log" | head -2; exit 1; }
grep -E "No errors" "$S/upload-$T.log"
git -C "$REPO" worktree remove --force "$W"
echo "shipped $C"
