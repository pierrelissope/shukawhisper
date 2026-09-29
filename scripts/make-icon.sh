#!/usr/bin/env bash
# Converts Resources/AppIcon.png (1024×1024, already shaped) into Resources/AppIcon.icns.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Resources/AppIcon.png"
SET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$SET"
for size in 16 32 128 256 512; do
    sips -z $size $size "$SRC" --out "$SET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$SRC" --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
echo "✓ Resources/AppIcon.icns"
