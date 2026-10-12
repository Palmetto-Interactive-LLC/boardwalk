#!/bin/zsh
# Boardwalk setup: builds the app from source, installs it to /Applications and opens it.
# Safe to run again any time to update.
set -euo pipefail
cd "${0:A:h}"

DEST="/Applications/Boardwalk.app"

# 1. macOS 14 (Sonoma) or newer
major="$(sw_vers -productVersion | cut -d. -f1)"
if (( major < 14 )); then
  echo "Boardwalk needs macOS 14 or newer. This Mac is on $(sw_vers -productVersion)." >&2
  exit 1
fi

# 2. Swift compiler (ships with Xcode or the free Command Line Tools)
if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "The Swift compiler isn't installed. Starting the Command Line Tools installer."
  echo "Run ./setup.sh again once it finishes."
  xcode-select --install || true
  exit 1
fi

# 3. Build
./scripts/build.sh

# 4. Install (quit a running copy first so it can be replaced)
pkill -x Boardwalk 2>/dev/null && sleep 1 || true
rm -rf "$DEST"
cp -R build/Boardwalk.app "$DEST"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"

# 5. Launch
open "$DEST"

cat <<'EOF'

Boardwalk is installed in /Applications and running.

  - Click Allow when macOS asks for Bluetooth access.
  - Make sure the treadmill is on and not connected to its phone app.
  - It connects on its own. The status at the bottom of the window turns green.

To keep it handy: right-click the Dock icon > Options > Keep in Dock.
EOF
