#!/bin/bash
# One-time setup: signing team (git-ignored), TVVLCKit, Xcode project.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodegen > /dev/null || { echo "xcodegen is needed: brew install xcodegen"; exit 1; }
python3 -I scripts/make_signing.py      # Config/Signing.xcconfig from your "Apple Development" identity
scripts/fetch_vlckit.sh                 # ~780 MB download, keeps only the tvOS and macOS slices
xcodegen generate
