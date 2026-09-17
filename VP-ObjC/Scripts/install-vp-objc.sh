#!/bin/bash
# audience: machine
# Installs the already-built ObjC Codenotch VP.app (from build-objc/, NOT the
# Swift build/ tree) into ~/Applications and loads its LaunchAgent. Mirrors
# Scripts/install-vp.sh (the Swift build's installer) but points at
# build-objc/ since Swift is unconditionally broken on this Mac for any
# AppKit import (Command Line Tools defect: two SwiftBridging module maps
# collide) — see VP-ObjC/README-VP.md for the full story.
#
# Does not build — build first with the clang command documented in
# VP-ObjC/README-VP.md, or your own equivalent script, so that
# VP-ObjC/../build-objc/Codenotch VP.app already exists.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_SRC="$REPO_DIR/build-objc/Codenotch VP.app"
APP_DST="$HOME/Applications/Codenotch VP.app"
PLIST_SRC="$REPO_DIR/VP-ObjC/Scripts/io.techbooster.codenotch-vp.plist"
PLIST_DST="$HOME/Library/LaunchAgents/io.techbooster.codenotch-vp.plist"

if [ ! -d "$APP_SRC" ]; then
  echo "error: $APP_SRC not found — build it first (see VP-ObjC/README-VP.md)" >&2
  exit 1
fi

mkdir -p "$HOME/Applications"
# ditto overwrites matching paths in place; no rm of any existing install.
ditto "$APP_SRC" "$APP_DST"
echo "Installed: $APP_DST"

mkdir -p "$HOME/Library/LaunchAgents"
if [ -f "$PLIST_DST" ]; then
  echo "LaunchAgent already present at $PLIST_DST — leaving it as is."
else
  cp "$PLIST_SRC" "$PLIST_DST"
  echo "Installed LaunchAgent: $PLIST_DST"
fi

launchctl unload "$PLIST_DST" >/dev/null 2>&1 || true
launchctl load "$PLIST_DST"
echo "Loaded. Codenotch VP (Objective-C build) should appear on the right edge of the main screen."
