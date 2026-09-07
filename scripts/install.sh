#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh
DESTINATION="$HOME/Applications/SpaceNameBar.app"
if pgrep -x SpaceNameBar >/dev/null; then
    echo "Quit SpaceNameBar before installing an update."
    exit 1
fi
mkdir -p "$HOME/Applications"
ditto dist/SpaceNameBar.app "$DESTINATION"
open "$DESTINATION"
echo "Installed: $DESTINATION"
