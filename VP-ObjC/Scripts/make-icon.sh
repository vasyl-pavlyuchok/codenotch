#!/bin/bash
# audience: machine
# Generates VP-ObjC/assets/icon/AppIcon.icns from VP-ObjC/assets/icon/icon-source.jpeg.
# Needs only clang + iconutil (both ship with the Command Line Tools / macOS).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ICON_DIR="$HERE/../assets/icon"
TMP="$(mktemp -d)"
clang -fobjc-arc -framework AppKit "$HERE/make-icon.m" -o "$TMP/make-icon"
"$TMP/make-icon" "$ICON_DIR/icon-source.jpeg" "$TMP/AppIcon.iconset"
iconutil -c icns "$TMP/AppIcon.iconset" -o "$ICON_DIR/AppIcon.icns"
echo "Wrote $ICON_DIR/AppIcon.icns"
