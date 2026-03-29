#!/bin/bash
set -euo pipefail

VERSION="$1"

xcodebuild archive \
  -scheme NetworkWatcher \
  -destination 'platform=macOS,arch=arm64' \
  -archivePath build/NetworkWatcher.xcarchive \
  CODE_SIGN_IDENTITY="Ixonae - GitHub Apps Signing" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$VERSION"

mkdir -p build/export
cp -R build/NetworkWatcher.xcarchive/Products/Applications/"Network Watcher.app" build/export/

cd build/export
zip -r ../../NetworkWatcher.zip "Network Watcher.app"
