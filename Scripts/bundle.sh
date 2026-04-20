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

echo "==> Ad-hoc signing with entitlements"
codesign --force --deep --sign - \
    --entitlements "Resources/Talkies.entitlements" \
    --options runtime \
    "$APP"

echo ""
echo "Built: $APP"
echo "Run:   open $APP"
echo ""
echo "First launch: grant Microphone + Accessibility when macOS prompts."
