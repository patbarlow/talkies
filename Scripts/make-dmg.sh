#!/bin/bash
# Bundle build/Yap.app into a drag-to-Applications DMG.
#
#   ./Scripts/make-dmg.sh           → build/Yap.dmg
#   ./Scripts/make-dmg.sh 0.2.0     → build/Yap-0.2.0.dmg
#
# Uses hdiutil's one-shot create (UDZO directly from a staging folder).
# We skip the RW-image → customize-in-Finder → convert flow because the
# convert step races against the system's DiskImages2 framework on
# modern macOS and fails with "Resource temporarily unavailable".
#
# Downside: no custom background or fixed icon positions — users see the
# default Finder layout with Yap.app and an Applications shortcut side
# by side. Good enough to install from, and always produces a valid DMG.
set -euo pipefail

cd "$(dirname "$0")/.."

APP="build/Yap.app"
if [[ ! -d "$APP" ]]; then
    echo "Error: $APP not found. Run ./Scripts/bundle.sh first."
    exit 1
fi

VERSION="${1:-}"
DMG_NAME="Yap"
[[ -n "$VERSION" ]] && DMG_NAME="Yap-$VERSION"
DMG="build/$DMG_NAME.dmg"

rm -f "$DMG"

STAGE=$(mktemp -d -t yap-dmg)
trap 'rm -rf "$STAGE"' EXIT

echo "==> Staging contents"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "==> Creating $DMG"
hdiutil create \
    -volname "$DMG_NAME" \
    -srcfolder "$STAGE" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG" >/dev/null

echo ""
echo "Created: $DMG ($(du -h "$DMG" | cut -f1))"
