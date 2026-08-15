#!/bin/bash
# Build AudioManager.app into dist/
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="dist/AudioManager.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/AudioManager "$APP/Contents/MacOS/AudioManager"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature is enough for local use; TCC (system-audio permission)
# needs a stable signed bundle to remember the grant.
codesign --force --sign - "$APP"

echo "Built $APP"
echo "Run with: open $APP"
