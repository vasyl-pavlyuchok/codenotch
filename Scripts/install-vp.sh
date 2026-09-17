#!/bin/bash
# audience: machine
# Installs the already-built Codenotch VP.app into ~/Applications and loads
# its LaunchAgent. Does not build — run `make -f Makefile-vp build` (or
# `make -f Makefile-vp install`, which does both) first.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_SRC="$REPO_DIR/build/Codenotch VP.app"
APP_DST="$HOME/Applications/Codenotch VP.app"
PLIST_SRC="$REPO_DIR/Scripts/io.techbooster.codenotch-vp.plist"
PLIST_DST="$HOME/Library/LaunchAgents/io.techbooster.codenotch-vp.plist"

if [ ! -d "$APP_SRC" ]; then
  echo "error: $APP_SRC not found — build it first (make -f Makefile-vp build)" >&2
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
echo "Loaded. Codenotch VP should appear on the right edge of the main screen."
