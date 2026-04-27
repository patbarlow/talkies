#!/bin/sh
set -e

echo "--- Installing xcodegen"
brew install xcodegen

echo "--- Generating Xcode project from ios/project.yml"
cd "$CI_PRIMARY_REPOSITORY_PATH/ios"
xcodegen generate

echo "--- Verifying generated Info.plist files"
echo "=== YapIOS/Info.plist ==="
cat YapIOS/Info.plist
echo "=== YapKeyboard/Info.plist ==="
cat YapKeyboard/Info.plist

echo "--- Project generated at ios/YapIOS.xcodeproj"
