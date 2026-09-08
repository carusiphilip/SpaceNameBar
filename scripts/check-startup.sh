#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --product SpaceNameBar
CHECK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/spacenamebar-launch.XXXXXX")"
trap 'rm -rf "$CHECK_DIR"' EXIT
PROBE_APP="$CHECK_DIR/StartupProbe.app"
mkdir -p "$PROBE_APP/Contents/MacOS"
cat > "$CHECK_DIR/Probe.swift" <<'SWIFT'
import AppKit
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let expiry = Timer.scheduledTimer(withTimeInterval: 90, repeats: false) { _ in NSApplication.shared.terminate(nil) }
app.run()
SWIFT
cat > "$PROBE_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.carusiphilip.SpaceNameBar.StartupProbe</string>
<key>CFBundleExecutable</key><string>StartupProbe</string>
<key>CFBundleName</key><string>StartupProbe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
swiftc "$CHECK_DIR/Probe.swift" -o "$PROBE_APP/Contents/MacOS/StartupProbe"
codesign --force --sign - "$PROBE_APP"
BIN_DIR="$(swift build --show-bin-path)"
"$BIN_DIR/SpaceNameBar" --check-startup-launch "$PROBE_APP"
