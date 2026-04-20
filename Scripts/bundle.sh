#!/bin/bash
# Build Talkies and package it into a proper .app bundle.
# Ad-hoc signed so Accessibility & Microphone permissions stick between runs.
set -euo pipefail

cd "$(dirname "$0")/.."

ARCH="$(uname -m)"
BIN_PATH=".build/${ARCH}-apple-macosx/release/Talkies"

echo "==> Building release binary ($ARCH)..."
swift build -c release --arch "$ARCH"

APP="build/Talkies.app"
echo "==> Assembling bundle at $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BIN_PATH" "$APP/Contents/MacOS/Talkies"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"

if [[ -f "Resources/AppIcon.icns" ]]; then
    cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
else
    echo "Warning: Resources/AppIcon.icns missing — run 'swift Scripts/make-icon.swift' to regenerate."
fi

# Signing identity: Developer ID Application tied to team T544U3WVL6.
# Required so restricted entitlements (Sign in with Apple) aren't stripped.
# Override via env: `SIGN_ID="Apple Development: ..."  ./Scripts/bundle.sh`
SIGN_ID="${SIGN_ID:-Developer ID Application: Pat Barlow (T544U3WVL6)}"
echo "==> Signing with: $SIGN_ID"
codesign --force --deep \
    --sign "$SIGN_ID" \
    --entitlements "Resources/Talkies.entitlements" \
    --options runtime \
    "$APP"

echo ""
echo "Built: $APP"
echo "Run:   open $APP"
echo ""
echo "First launch: grant Microphone + Accessibility when macOS prompts."
