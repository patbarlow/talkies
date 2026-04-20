#!/bin/bash
# Build Yap and package it into a proper .app bundle.
set -euo pipefail

cd "$(dirname "$0")/.."

ARCH="$(uname -m)"
BIN_PATH=".build/${ARCH}-apple-macosx/release/Yap"

echo "==> Building release binary ($ARCH)..."
swift build -c release --arch "$ARCH"

APP="build/Yap.app"
echo "==> Assembling bundle at $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BIN_PATH" "$APP/Contents/MacOS/Yap"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"

if [[ -f "Resources/AppIcon.icns" ]]; then
    cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
else
    echo "Warning: Resources/AppIcon.icns missing — run 'swift Scripts/make-icon.swift' to regenerate."
fi

# Signing identity. Override via env:
#   SIGN_ID="-"  ./Scripts/bundle.sh                         # ad-hoc (fastest, resets perms each rebuild)
#   SIGN_ID="Developer ID Application: ..."  ./bundle.sh     # stable signature → perms persist, notarization-ready
SIGN_ID="${SIGN_ID:-Developer ID Application: Pat Barlow (T544U3WVL6)}"

echo "==> Signing with: $SIGN_ID"
codesign --force --deep \
    --sign "$SIGN_ID" \
    --entitlements "Resources/Yap.entitlements" \
    --options runtime \
    "$APP"

echo ""
echo "Built: $APP"
echo "Run:   open $APP"
