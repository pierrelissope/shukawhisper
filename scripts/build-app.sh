#!/usr/bin/env bash
# Builds ShukaWhisper.app into .build/ and signs it.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=".build/ShukaWhisper.app"
IDENTITY="${SIGNING_IDENTITY:-ShukaWhisper Local Signing}"

swift build -c release --product ShukaWhisper

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/ShukaWhisper" "$APP/Contents/MacOS/ShukaWhisper"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    codesign --force --sign "$IDENTITY" --identifier dev.shukawhisper.app "$APP"
    echo "✓ Signed with \"$IDENTITY\""
else
    codesign --force --sign - --identifier dev.shukawhisper.app "$APP"
    echo "⚠ Ad-hoc signed. Run 'make cert' once so permissions survive rebuilds."
fi
echo "✓ Built $APP"
