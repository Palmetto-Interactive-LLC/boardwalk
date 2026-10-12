#!/bin/zsh
# Builds build/Boardwalk.app from source. Does not install or launch it.
# Used by setup.sh and by CI.
set -euo pipefail
cd "${0:A:h}/.."

APP="build/Boardwalk.app"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Rendering icon"
swift scripts/make_icon.swift "$WORK/icon_1024.png"
mkdir "$WORK/AppIcon.iconset"
for s in 16 32 128 256 512; do
  sips -z $s $s "$WORK/icon_1024.png" --out "$WORK/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) "$WORK/icon_1024.png" --out "$WORK/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$WORK/AppIcon.iconset" -o "$WORK/AppIcon.icns"

echo "==> Compiling"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$WORK/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
swiftc -O -swift-version 5 -parse-as-library Sources/Boardwalk.swift -o "$APP/Contents/MacOS/Boardwalk"

IDENTITY="$(scripts/signing-identity.sh)"
echo "==> Signing as: $IDENTITY"
codesign --force --sign "$IDENTITY" "$APP"

echo "Built $APP"
