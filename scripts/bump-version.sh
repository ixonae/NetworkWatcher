#!/bin/bash
set -euo pipefail

VERSION="$1"
PROJECT_FILE="NetworkWatcher.xcodeproj/project.pbxproj"

sed -i '' "s/MARKETING_VERSION = [^;]*/MARKETING_VERSION = $VERSION/" "$PROJECT_FILE"
sed -i '' "s/CURRENT_PROJECT_VERSION = [^;]*/CURRENT_PROJECT_VERSION = $VERSION/" "$PROJECT_FILE"
