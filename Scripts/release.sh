#!/bin/bash
# Cut a notarized, Sparkle-signed release.
#
#   ./Scripts/release.sh 0.2.0
#
# What it does:
#   1. Bumps CFBundleShortVersionString and CFBundleVersion in Info.plist
#   2. Builds + signs via bundle.sh (Sparkle framework embedded, entitlements applied)
#   3. Zips, submits to Apple notary, staples the ticket, re-zips for distribution
#   4. Creates a drag-to-Applications DMG, notarizes + staples it too
#   5. Signs the zip with Sparkle's sign_update (EdDSA private key in keychain)
#   6. Prepends an <item> to docs/appcast.xml pointing at the GitHub release asset
#   7. Commits Info.plist + appcast.xml, tags v<version>, pushes everything
#   8. Creates a GitHub release and uploads Yap-<version>.zip + .dmg
#
# Prerequisites (one-time per machine):
#   - xcrun notarytool store-credentials "yap-notary" ...  (see release.sh comment below)
#   - Sparkle keys generated via bin/generate_keys (private stored in keychain)
#   - `gh` CLI authenticated
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
    echo "Usage: $0 <version>    e.g. $0 0.2.0"
    exit 1
fi
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: version must be X.Y.Z, got: $VERSION"
    exit 1
fi

TAG="v$VERSION"

if [[ -n "$(git status --porcelain)" ]]; then
    echo "Error: working tree is dirty. Commit or stash first."
    git status --short
    exit 1
fi

if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "Error: tag $TAG already exists."
    exit 1
fi

# ---- Version bump -----------------------------------------------------------

BUILD=$(( $(git rev-list --count HEAD) + 1 ))
echo "==> Setting version $VERSION (build $BUILD) in Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" Resources/Info.plist

# ---- Build, sign ------------------------------------------------------------

./Scripts/bundle.sh

APP="build/Yap.app"
ZIP="build/Yap-$VERSION.zip"

# ---- Notarize ---------------------------------------------------------------

# Strip AppleDouble files Synology Drive adds after codesigning — they cause
# `codesign --deep --strict` to fail, which is how Sparkle validates updates.
strip_app_detritus() {
    find "$APP" -name "._*" -delete 2>/dev/null || true
    xattr -cr "$APP" 2>/dev/null || true
}

echo "==> Packing zip for notarization"
strip_app_detritus
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Submitting to Apple notary service (usually 1-3 min)"
xcrun notarytool submit "$ZIP" \
    --keychain-profile "yap-notary" \
    --wait

echo "==> Stapling notarization ticket"
xcrun stapler staple "$APP"

# Re-zip with stapled app for distribution.
strip_app_detritus
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Verifying Gatekeeper accepts the notarized build"
spctl -a -vvv -t execute "$APP"

# ---- DMG for humans (Sparkle uses the zip below) ----------------------------

DMG="build/Yap-$VERSION.dmg"
./Scripts/make-dmg.sh "$VERSION"

echo "==> Notarizing DMG (avoids a 'cannot check DMG' prompt on first open)"
xcrun notarytool submit "$DMG" \
    --keychain-profile "yap-notary" \
    --wait
xcrun stapler staple "$DMG"

# ---- Sign for Sparkle -------------------------------------------------------

SIGN_UPDATE=$(find .build/artifacts -name "sign_update" -perm +111 -type f | head -1)
if [[ -z "$SIGN_UPDATE" ]]; then
    echo "Error: sign_update tool not found in .build/artifacts. Run 'swift build' first."
    exit 1
fi

echo "==> Signing zip with Sparkle's EdDSA key"
SIG_LINE=$("$SIGN_UPDATE" "$ZIP")
# Expected output: sparkle:edSignature="..." length="..."

# ---- Update appcast ---------------------------------------------------------

PUBDATE=$(date -u "+%a, %d %b %Y %H:%M:%S +0000")
DOWNLOAD_URL="https://github.com/patbarlow/talkies/releases/download/$TAG/Yap-$VERSION.zip"

echo "==> Inserting <item> into docs/appcast.xml"
VERSION=$VERSION BUILD=$BUILD PUBDATE=$PUBDATE DOWNLOAD_URL=$DOWNLOAD_URL SIG_LINE=$SIG_LINE \
python3 <<'PYEOF'
import os, pathlib

version   = os.environ["VERSION"]
build     = os.environ["BUILD"]
pubdate   = os.environ["PUBDATE"]
url       = os.environ["DOWNLOAD_URL"]
sig_line  = os.environ["SIG_LINE"].strip()

marker = "<!-- RELEASES_INSERT_HERE -->"
item = f"""<item>
            <title>Version {version}</title>
            <pubDate>{pubdate}</pubDate>
            <sparkle:version>{build}</sparkle:version>
            <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <enclosure url="{url}" {sig_line} type="application/octet-stream" />
        </item>
        {marker}"""

path = pathlib.Path("docs/appcast.xml")
text = path.read_text()
if marker not in text:
    raise SystemExit(f"Marker {marker!r} not found in {path}")
path.write_text(text.replace(marker, item, 1))
print(f"appcast.xml updated with v{version}")
PYEOF

# ---- Commit, tag, push, release --------------------------------------------

echo "==> Committing + tagging + pushing"
git add Resources/Info.plist docs/appcast.xml
git commit -m "Release $TAG"
git tag "$TAG"
git push origin main
git push origin "$TAG"

echo "==> Creating GitHub release and uploading assets"
gh release create "$TAG" "$ZIP" "$DMG" \
    --title "Yap $VERSION" \
    --notes "Notarized, Sparkle-signed. Download the DMG to install, or existing users will pick up the update from Check for Updates…"

echo ""
echo "Released $TAG"
echo "Zip (Sparkle): $ZIP"
echo "DMG (humans):  $DMG"
echo "Download URL:  $DOWNLOAD_URL"
echo "Appcast:       https://patbarlow.github.io/talkies/appcast.xml"
