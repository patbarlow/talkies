#!/bin/bash
# Build, sign, notarize, and staple a distributable Yap.app.
#
# Prerequisites (run ONCE per machine):
#   1. Generate an app-specific password at appleid.apple.com → Sign-In and Security.
#   2. Store the notary credentials in the keychain:
#        xcrun notarytool store-credentials "yap-notary" \
#          --apple-id "your@apple.id" \
#          --team-id  "T544U3WVL6" \
#          --password "app-specific-password"
#
# Then, per release, just:
#   ./Scripts/release.sh
set -euo pipefail

cd "$(dirname "$0")/.."

# Reuse the main bundle script for signing.
./Scripts/bundle.sh

APP="build/Yap.app"
ZIP="build/Yap.zip"

echo "==> Packing zip for notarization"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Submitting to Apple notary service (usually ~1–3 minutes)"
xcrun notarytool submit "$ZIP" \
    --keychain-profile "yap-notary" \
    --wait

echo "==> Stapling notarization ticket to the app"
xcrun stapler staple "$APP"

echo "==> Repacking zip with the stapled app (for distribution)"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Verifying with Gatekeeper"
spctl -a -vvv -t execute "$APP"
stapler validate "$APP"

echo ""
echo "Notarized & stapled: $APP"
echo "Distributable zip:   $ZIP"
