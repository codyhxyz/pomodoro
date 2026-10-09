#!/bin/bash
# Usage: make-dmg.sh <path/to/App.app> <output.dmg>
# Builds a drag-to-Applications installer disk image.
set -euo pipefail

app="$1"
out="$2"
name="$(basename "$app" .app)"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT

cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"

mkdir -p "$(dirname "$out")"
rm -f "$out"
hdiutil create -volname "$name" -srcfolder "$staging" -fs HFS+ -format UDZO -ov "$out" >/dev/null

if identity="$(codesign -dv "$app" 2>&1 | sed -n 's/^Authority=\(Developer ID Application.*\)/\1/p' | head -1)" && [ -n "$identity" ]; then
  codesign --sign "$identity" "$out"
fi
echo "$out"
