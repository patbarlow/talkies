#!/bin/sh
set -e

echo "--- Installing xcodegen"
brew install xcodegen

echo "--- Generating Xcode project from ios/project.yml"
cd "$CI_PRIMARY_REPOSITORY_PATH/ios"
xcodegen generate

echo "--- Project generated at ios/YapIOS.xcodeproj"
