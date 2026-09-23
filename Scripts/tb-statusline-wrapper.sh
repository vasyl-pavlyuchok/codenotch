#!/bin/bash
# audience: machine
# Source of truth for ~/.claude/hooks/tb-statusline-wrapper.sh. Install with
# Scripts/install-statusline-sink.sh — settings.json points at the copy in
# ~/.claude/hooks, never at this repo, because the repo has already moved once
# (~/Documents/TechBooster/own -> ~/Documents/Claude/vp_designs) and a moved
# repo must not be able to break the CEO's status line.
#
# Reads the status line's stdin JSON once, fans it out to tb-usage-sink.js
# (which writes ~/.claude/state/usage-5h.json for Codenotch VP and for
# ~/.claude/bin/tb_usage_breaker.py) and then runs the real status line
# unchanged, so nothing about today's status line output changes.
#
# DELIBERATELY NOT `set -e`: this script sits in front of the CEO's status
# line. If anything here fails, the status line must still render. Every step
# is individually guarded.

SINK="$HOME/.claude/hooks/tb-usage-sink.js"
STATUSLINE="$HOME/.claude/hooks/gsd-statusline.js"

INPUT="$(cat)"

# The sink is best-effort and must never delay or break the status line.
if [ -f "$SINK" ]; then
  printf '%s' "$INPUT" | node "$SINK" >/dev/null 2>&1 || true
fi

if [ -f "$STATUSLINE" ]; then
  printf '%s' "$INPUT" | node "$STATUSLINE"
fi
exit 0
