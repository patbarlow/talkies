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
mkdir -p "$APP/Contents/Frameworks"

cp "$BIN_PATH" "$APP/Contents/MacOS/Yap"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"

if [[ -f "Resources/AppIcon.icns" ]]; then
    cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
else
    echo "Warning: Resources/AppIcon.icns missing — run 'swift Scripts/make-icon.swift' to regenerate."
fi

# Embed Sparkle.framework for auto-updates. SPM fetched it into the artifact
# cache; find the macOS slice of the XCFramework and copy it into the bundle.
SPARKLE_XC=$(find .build/artifacts -type d -path "*Sparkle.xcframework*Sparkle.framework" | head -1)
if [[ -z "$SPARKLE_XC" ]]; then
    echo "Error: Sparkle.framework not found in .build/artifacts. Run 'swift build' first."
    exit 1
fi
echo "==> Copying Sparkle.framework from $SPARKLE_XC"
# ditto --noextattr --norsrc preserves symlinks but strips any resource forks /
# extended attributes that Synology Drive may have added to the source tree.
ditto --noextattr --norsrc "$SPARKLE_XC" "$APP/Contents/Frameworks/Sparkle.framework"

# SwiftPM executables don't embed @executable_path/../Frameworks in the rpath
# the way Xcode does, so dyld can't find Sparkle at launch. Patch the binary
# after build; it'll be re-signed below so the modification is sealed in.
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Yap" 2>/dev/null || true

# Signing identity. Override via env:
#   SIGN_ID="-"  ./Scripts/bundle.sh                         # ad-hoc
#   SIGN_ID="Developer ID Application: ..."  ./bundle.sh     # distribution
SIGN_ID="${SIGN_ID:-Developer ID Application: Pat Barlow (T544U3WVL6)}"

# Helper: strip xattrs and AppleDouble files from a path right before signing.
# Called per-component because Synology Drive can re-add ._* files between ops.
strip_detritus() {
    xattr -cr "$1" 2>/dev/null || true
    find "$1" -name "._*" -delete 2>/dev/null || true
}

echo "==> Signing with: $SIGN_ID"

# Sparkle's XPC services and embedded Updater.app ship with their own
# entitlements (e.g. the Downloader XPC has no-sandbox, the Installer XPC
# needs specific privileges). Re-sign them preserving those entitlements so
# our app's entitlements aren't applied over theirs.
for nested in \
    "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc" \
    "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc" \
    "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app" \
    "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
do
    if [[ -e "$nested" ]]; then
        strip_detritus "$nested"
        codesign --force --sign "$SIGN_ID" --options runtime \
            --preserve-metadata=entitlements "$nested"
    fi
done

# Sign the framework itself (which seals the nested components above).
strip_detritus "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign "$SIGN_ID" --options runtime \
    "$APP/Contents/Frameworks/Sparkle.framework"

# Finally, sign the outer app bundle with Yap's own entitlements. No --deep
# here — Sparkle is already correctly signed; --deep would overwrite with
# Yap's entitlements and break the Sparkle XPC services.
strip_detritus "$APP"
codesign --force --sign "$SIGN_ID" \
    --entitlements "Resources/Yap.entitlements" \
    --options runtime \
    "$APP"

echo ""
echo "Built: $APP"
echo "Run:   open $APP"
