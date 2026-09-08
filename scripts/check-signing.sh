#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/spacenamebar-signing.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
APP="$TEST_DIR/SignatureProbe.app"
ditto dist/SpaceNameBar.app "$APP"
codesign -d -r "$TEST_DIR/requirements" "$APP"
BEFORE="$(codesign -dvv "$APP" 2>&1 | sed -n 's/^CDHash=//p')"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 999999' "$APP/Contents/Info.plist"
python3 scripts/sign.py "$APP"
AFTER="$(codesign -dvv "$APP" 2>&1 | sed -n 's/^CDHash=//p')"
[ -n "$BEFORE" ] && [ -n "$AFTER" ] && [ "$BEFORE" != "$AFTER" ]
REQUIREMENT="$(sed -n 's/^designated => //p' "$TEST_DIR/requirements")"
[ -n "$REQUIREMENT" ]
codesign --verify --strict --test-requirement "=$REQUIREMENT" "$APP"
echo 'PASS: changed app content retains the previous build signing requirement.'

codesign --force --sign - "$APP"
if codesign --verify --strict --test-requirement "=$REQUIREMENT" "$APP" 2>/dev/null; then
    echo 'FAIL: another signer satisfied the persistent identity.' >&2
    exit 1
fi
echo 'PASS: matching bundle ID with another signer is rejected.'
