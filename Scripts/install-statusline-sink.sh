#!/bin/bash
# audience: machine
# Installs the status line usage sink into ~/.claude/hooks and points
# ~/.claude/settings.json's statusLine at the wrapper.
#
# Why this exists (VP05, 23-sep-2026): Codenotch VP used to read the OAuth
# token out of the login keychain every 60s to fill its "Sesión actual" and
# "Esta semana · todos los modelos" rows. That is what produced the repeated
# "Codenotch VP wants to access key Claude Code-credentials" password dialog.
# Both of those numbers are already in the JSON Claude Code hands its status
# line on every refresh, so the sink writes them to a file and the app reads
# the file — no keychain, no network.
#
# Side effect worth knowing: ~/.claude/state/usage-5h.json is also what
# ~/.claude/bin/tb_usage_breaker.py reads to decide whether a delegation is
# too close to the 5h ceiling. That file had not been written since
# 17-sep-2026 (nothing wrote it — the sink was never wired), so the breaker
# was running on a frozen reading. This repairs that too.
#
# Idempotent. Backs up settings.json before touching it. Run with --dry-run to
# see what it would do.

set -euo pipefail

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_DIR="$HOME/.claude/hooks"
SETTINGS="$HOME/.claude/settings.json"
WRAPPER_DST="$HOOKS_DIR/tb-statusline-wrapper.sh"
SINK_DST="$HOOKS_DIR/tb-usage-sink.js"

say() { printf '%s\n' "$*"; }

if [ ! -f "$REPO_DIR/Scripts/tb-statusline-wrapper.sh" ] || [ ! -f "$REPO_DIR/Scripts/tb-usage-sink.js" ]; then
  say "ERROR: sources not found under $REPO_DIR/Scripts" >&2
  exit 1
fi

if [ "$DRY_RUN" = "1" ]; then
  say "DRY RUN — nothing will be written."
  say "  would copy Scripts/tb-statusline-wrapper.sh -> $WRAPPER_DST"
  say "  would copy Scripts/tb-usage-sink.js         -> $SINK_DST"
  say "  would set statusLine.command in $SETTINGS to:"
  say "      bash $WRAPPER_DST"
  exit 0
fi

mkdir -p "$HOOKS_DIR" "$HOME/.claude/state"
install -m 755 "$REPO_DIR/Scripts/tb-statusline-wrapper.sh" "$WRAPPER_DST"
install -m 755 "$REPO_DIR/Scripts/tb-usage-sink.js" "$SINK_DST"
say "installed: $WRAPPER_DST"
say "installed: $SINK_DST"

BACKUP="$SETTINGS.bak-$(date +%Y%m%d-%H%M%S)"
cp "$SETTINGS" "$BACKUP"
say "backed up settings.json -> $BACKUP"

WRAPPER_DST="$WRAPPER_DST" python3 - "$SETTINGS" <<'PY'
import json, os, sys
path = sys.argv[1]
wrapper = os.environ["WRAPPER_DST"]
with open(path) as fh:
    settings = json.load(fh)
settings["statusLine"] = {"type": "command", "command": "bash %s" % wrapper}
with open(path, "w") as fh:
    json.dump(settings, fh, indent=2)
    fh.write("\n")
print("statusLine.command -> bash %s" % wrapper)
PY

say "Done. The status line output itself is unchanged; it now also writes"
say "~/.claude/state/usage-5h.json on every refresh."
