#!/bin/bash
# audience: machine
# Installs the already-built ObjC Codenotch VP.app (from build-objc/, NOT the
# Swift build/ tree) into /Applications and loads its LaunchAgent. Mirrors
# Scripts/install-vp.sh (the Swift build's installer) but points at
# build-objc/ since Swift is unconditionally broken on this Mac for any
# AppKit import (Command Line Tools defect: two SwiftBridging module maps
# collide) — see VP-ObjC/README-VP.md for the full story.
#
# Lives in /Applications, not ~/Applications (CEO request, 18-sep-2026:
# "quiero que viva donde todas las apps" -- he couldn't find ~/Applications
# in Finder, since it's hidden from the sidebar by default). /Applications
# is group-writable by `admin` on this Mac, so this needs no sudo.
#
# Does not build — build first with the clang command documented in
# VP-ObjC/README-VP.md, or your own equivalent script, so that
# VP-ObjC/../build-objc/Codenotch VP.app already exists.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_SRC="$REPO_DIR/build-objc/Codenotch VP.app"
APP_DST="/Applications/Codenotch VP.app"
PLIST_SRC="$REPO_DIR/VP-ObjC/Scripts/io.techbooster.codenotch-vp.plist"
PLIST_DST="$HOME/Library/LaunchAgents/io.techbooster.codenotch-vp.plist"

if [ ! -d "$APP_SRC" ]; then
  echo "error: $APP_SRC not found — build it first (see VP-ObjC/README-VP.md)" >&2
  exit 1
fi

# ditto overwrites matching paths in place; no rm of any existing install.
ditto "$APP_SRC" "$APP_DST"
echo "Installed: $APP_DST"

mkdir -p "$HOME/Library/LaunchAgents"
# Always resync from the repo's plist -- an install that silently kept a
# stale copy forever (its old behaviour) is the same bug class as the
# Info.plist/icon drift this repo already hit once this session.
cp "$PLIST_SRC" "$PLIST_DST"
echo "Synced LaunchAgent: $PLIST_DST"

launchctl unload "$PLIST_DST" >/dev/null 2>&1 || true
launchctl load "$PLIST_DST"
echo "Loaded. Codenotch VP (Objective-C build) should appear on the right edge of the main screen."
echo
echo "It will never show a keychain password prompt (SecKeychainSetUserInteractionAllowed"
echo "is called at launch, see README-VP.md) -- nothing extra to run for that."
echo
echo "One more step for the session/weekly rows to show real numbers instead of staying"
echo "empty: wire the status line sink once with:"
echo "  $REPO_DIR/Scripts/install-statusline-sink.sh"
