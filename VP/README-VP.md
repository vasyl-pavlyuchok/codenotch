<!-- audience: machine -->
# Codenotch VP

A tiny macOS notch showing only Claude and Codex usage, built with plain
`swiftc` + AppKit/Core Graphics (no Xcode, no SwiftUI). Same visual language
as upstream Codenotch: a black pill on the right screen edge with concave
joins to the bezel, one ring per provider, a hover card with bars.

## Build / run / install

```
make -f Makefile-vp build     # swiftc build, into build/Codenotch VP.app
make -f Makefile-vp run       # build + open the app
make -f Makefile-vp install   # build + copy to ~/Applications + load LaunchAgent
```

`install` is the one command the CEO runs. It is idempotent: it will not
overwrite an existing LaunchAgent plist under `~/Library/LaunchAgents/`, and
it uses `ditto` (not `rm` + copy) to update the app bundle in place.

## Wiring up the real 5h/weekly numbers (one line to add)

The app reads `~/.claude/state/usage-5h.json` every 15 seconds for the
"Sesión actual" and "Esta semana · todos los modelos" rows. That file is only
kept fresh if something writes it — today nothing does, so until this line is
added those two bars show whatever was last written (or nothing).

`Scripts/tb-usage-sink.js` is that "something": it reads the exact same JSON
Claude Code already feeds the status line on every refresh
(`rate_limits.five_hour` / `rate_limits.seven_day`) and writes it to
`~/.claude/state/usage-5h.json` atomically (temp file + rename). It keeps the
file's existing keys (`used_percentage`, `resets_at`, `updated_at` — the
exact shape `~/.claude/bin/tb_usage_breaker.py` already reads) and only adds
`seven_day` as a new sibling object, so the breaker keeps working unchanged.

To wire it in, add ONE line to `~/.claude/settings.json`'s `statusLine`
command, pointing it at `Scripts/tb-statusline-wrapper.sh` instead of the
status line script directly:

```
"command": "/Users/vasylpavlyuchok/Documents/TechBooster/own/codenotch/Scripts/tb-statusline-wrapper.sh"
```

That wrapper tees stdin to the sink and then execs the existing
`~/.claude/hooks/gsd-statusline.js` unchanged — the status line's own output
never changes, only a side file gets written.

Nothing in this repo installs that line automatically; it is not this task's
call to edit `~/.claude/settings.json`. This file is the documentation for
doing it by hand, per the task brief.

## The Fable bar (third row on the Claude card)

Read-only: the app reads the Claude Code OAuth token from the macOS login
keychain item `Claude Code-credentials` (never writes it, never logs it,
never stores it to disk) and calls
`GET https://api.anthropic.com/api/oauth/usage` with
`Authorization: Bearer <token>` and `anthropic-beta: oauth-2025-04-20` — the
same request `Sources/Providers/ClaudeOAuthProvider.swift` makes. It looks
for a window in the response's `limits` array whose `kind` or
`scope.model.displayName` contains "fable" (case-insensitive). If the
response never names one, the third bar is simply hidden — logged to stderr
once, not on every poll — never invented.

Polls at most once every 60 seconds; on HTTP 429 it backs off (60s, doubling,
capped at 15 minutes), matching the upstream provider's own backoff curve.

## Codex

Codex is not installed on this Mac (`~/.codex` does not exist). The ring
shows grey with "—" and the hover card says "Codex no está instalado" — no
data is invented. `VP/CodexUsageReader.swift` implements the real reader
(`~/.codex/auth.json` → `chatgpt.com/backend-api/wham/usage`,
`rate_limit.primary_window`) against the same shapes
`Sources/Providers/CodexLocalProvider.swift` and `CodexUsage.swift` use, so
if Codex is ever installed on this Mac the ring starts showing real numbers
without any code change — only `isInstalled` flips.

## What is out of scope (per the task brief)

Mobile pairing, auto-update, 80%/100% notifications, Accessibility
permission, drag-to-move along the edge. Position is read from
`UserDefaults` (`VPNotchYOffset`) but nothing yet writes to it — the notch
always opens vertically centred on the main screen's right edge.
