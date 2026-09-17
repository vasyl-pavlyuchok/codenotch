#!/bin/bash
# audience: machine
# Tees the status line's stdin JSON to tb-usage-sink.js (which writes
# ~/.claude/state/usage-5h.json for Codenotch VP) and then execs the
# existing status line unchanged, so nothing about today's status line output
# changes. Not installed by this task — see VP/README-VP.md for the one
# settings.json line the CEO adds to wire this in.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATUSLINE="$HOME/.claude/hooks/gsd-statusline.js"

# Read stdin once, fan it out to the sink and to the real status line.
INPUT="$(cat)"
printf '%s' "$INPUT" | node "$SCRIPT_DIR/tb-usage-sink.js" || true
printf '%s' "$INPUT" | node "$STATUSLINE"
