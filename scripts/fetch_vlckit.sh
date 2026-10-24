#!/bin/bash
# Fetch VLCKit 3.6.0 and keep only what the two apps use: the tvOS slices (TVVLCKit, Apple TV app)
# and the macOS slice (VLCKit, Mac app).
# Source: the VLCKit-all xcframework published by github.com/tylerjonesio/vlckit-spm (checksum pinned).
# Usage: scripts/fetch_vlckit.sh [path-to-already-downloaded-zip]
set -euo pipefail
cd "$(dirname "$0")/.."
URL=https://github.com/tylerjonesio/vlckit-spm/releases/download/3.6.0/VLCKit-all.xcframework.zip
SUM=5da4747e001900bbb4153f58db2be4695096c9c2350aea00376ad67b39c053f6
TV=Vendor/TVVLCKit.xcframework
MAC=Vendor/VLCKit.xcframework
if [ -d "$TV/tvos-arm64" ] && [ -d "$MAC/macos-arm64_x86_64" ]; then echo "VLCKit already in Vendor/"; exit 0; fi
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
ZIP=${1:-$TMP/vlc.zip}
[ -f "$ZIP" ] || curl -fL -o "$ZIP" "$URL"
echo "$SUM  $ZIP" | shasum -a 256 -c -
mkdir -p Vendor

if [ ! -d "$TV/tvos-arm64" ]; then
unzip -q "$ZIP" 'VLCKit-all.xcframework/tvos-arm64/TVVLCKit.framework/*' 'VLCKit-all.xcframework/tvos-arm64_x86_64-simulator/TVVLCKit.framework/*' -d "$TMP/tv"
rm -rf "$TV" && mv "$TMP/tv/VLCKit-all.xcframework" "$TV"
cat > "$TV/Info.plist" <<'PL'
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
echo "TVVLCKit ready in $TV"
fi

if [ ! -d "$MAC/macos-arm64_x86_64" ]; then
unzip -q "$ZIP" 'VLCKit-all.xcframework/macos-arm64_x86_64/VLCKit.framework/*' -d "$TMP/mac"
rm -rf "$MAC" && mv "$TMP/mac/VLCKit-all.xcframework" "$MAC"
cat > "$MAC/Info.plist" <<'PL'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AvailableLibraries</key>
	<array>
		<dict>
			<key>BinaryPath</key><string>VLCKit.framework/Versions/A/VLCKit</string>
			<key>LibraryIdentifier</key><string>macos-arm64_x86_64</string>
			<key>LibraryPath</key><string>VLCKit.framework</string>
			<key>SupportedArchitectures</key><array><string>arm64</string><string>x86_64</string></array>
			<key>SupportedPlatform</key><string>macos</string>
		</dict>
	</array>
	<key>CFBundlePackageType</key><string>XFWK</string>
	<key>XCFrameworkFormatVersion</key><string>1.0</string>
</dict>
</plist>
PL
echo "VLCKit (macOS) ready in $MAC"
fi
