#!/bin/bash
# Fetch TVVLCKit 3.6.0 (the tvOS build of VLCKit) and keep only the two tvOS slices.
# Source: the VLCKit-all xcframework published by github.com/tylerjonesio/vlckit-spm (checksum pinned).
# Usage: scripts/fetch_vlckit.sh [path-to-already-downloaded-zip]
set -euo pipefail
cd "$(dirname "$0")/.."
URL=https://github.com/tylerjonesio/vlckit-spm/releases/download/3.6.0/VLCKit-all.xcframework.zip
SUM=5da4747e001900bbb4153f58db2be4695096c9c2350aea00376ad67b39c053f6
OUT=Vendor/TVVLCKit.xcframework
[ -d "$OUT/tvos-arm64" ] && { echo "TVVLCKit already in $OUT"; exit 0; }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
ZIP=${1:-$TMP/vlc.zip}
[ -f "$ZIP" ] || curl -fL -o "$ZIP" "$URL"
echo "$SUM  $ZIP" | shasum -a 256 -c -
unzip -q "$ZIP" 'VLCKit-all.xcframework/tvos-arm64/TVVLCKit.framework/*' 'VLCKit-all.xcframework/tvos-arm64_x86_64-simulator/TVVLCKit.framework/*' -d "$TMP/x"
mkdir -p Vendor && rm -rf "$OUT" && mv "$TMP/x/VLCKit-all.xcframework" "$OUT"
cat > "$OUT/Info.plist" <<'PL'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AvailableLibraries</key>
	<array>
		<dict>
			<key>BinaryPath</key><string>TVVLCKit.framework/TVVLCKit</string>
			<key>LibraryIdentifier</key><string>tvos-arm64</string>
			<key>LibraryPath</key><string>TVVLCKit.framework</string>
			<key>SupportedArchitectures</key><array><string>arm64</string></array>
			<key>SupportedPlatform</key><string>tvos</string>
		</dict>
		<dict>
			<key>BinaryPath</key><string>TVVLCKit.framework/TVVLCKit</string>
			<key>LibraryIdentifier</key><string>tvos-arm64_x86_64-simulator</string>
			<key>LibraryPath</key><string>TVVLCKit.framework</string>
			<key>SupportedArchitectures</key><array><string>arm64</string><string>x86_64</string></array>
			<key>SupportedPlatform</key><string>tvos</string>
			<key>SupportedPlatformVariant</key><string>simulator</string>
		</dict>
	</array>
	<key>CFBundlePackageType</key><string>XFWK</string>
	<key>XCFrameworkFormatVersion</key><string>1.0</string>
</dict>
</plist>
PL
echo "TVVLCKit ready in $OUT"
