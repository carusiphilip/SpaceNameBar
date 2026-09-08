#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="$PWD/dist/SpaceNameBar.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/SpaceNameBar" "$APP/Contents/MacOS/SpaceNameBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
python3 scripts/sign.py "$APP"
codesign --verify --strict "$APP"
echo "Built: $APP"
