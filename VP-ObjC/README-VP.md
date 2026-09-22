<!-- audience: machine -->
# Codenotch VP (Objective-C build)

## Why Objective-C, not Swift (17-sep-2026)

Swift is broken on this Mac right now for any program that imports AppKit —
even `import AppKit; print("x")` alone in a file fails with "redefinition of
module 'SwiftBridging'". Two files under
`/Library/Developer/CommandLineTools/usr/include/swift/` both declare the
same internal module; this is a Command Line Tools installation defect,
confirmed and reproduced on 17-sep-2026, not a bug in this project's code.
Fixing it needs a sudo reinstall of Command Line Tools, which wasn't
available at the time this port was built.

Objective-C compiled with plain `clang` is confirmed working on this same
Mac (`clang -fobjc-arc -framework AppKit test.m -o test` compiles and runs
instantly). So this folder, `VP-ObjC/`, is a straight, unabridged port of the
reviewed `VP/*.swift` reference (18 files, ~1400 lines, already through an
independent adversarial code review — verdict APTO CON RESERVAS, no
critical/high findings) into 9 Objective-C files, same logic, same data, same
visual language. The Swift files in `VP/` are left untouched as the reference
spec and design history; they are not deleted.

If Swift is fixed on this Mac later (Command Line Tools reinstalled), the
`VP/` Swift version and its `Makefile-vp` remain the way to build it — this
folder does not replace that path, it exists because that path is currently
unusable.

## Files

- `Palette.h/.m` — colors (#00FF88/​#F2FF00/​#FF3F00 + white-alpha tracks) and
  usage-band thresholds (50%/70%), from `VP/Palette.swift` + `VP/UsageBand.swift`.
- `Glyphs.h/.m` — the SVG "d"-string parser and the two embedded Claude/OpenAI
  glyph paths, from `VP/SVGPath.swift` + `VP/Glyphs.swift`.
- `UsageModel.h/.m` — `VPLimitRow`, `VPProviderReading`, and the Spanish
  reset-time label ("Se reinicia a las 8:20" / "Se reinicia mar 14:00"), from
  `VP/UsageModel.swift` + `VP/UsageBand.swift` + `VP/ResetTime.swift`.
- `ClaudeUsageFile.h/.m` — reads `~/.claude/state/usage-5h.json`, computes
  `isStale` (30-min window), and the working/waiting session-file signal,
  from `VP/ClaudeUsageFile.swift` + `VP/SessionState.swift`.
- `ClaudeOAuthUsage.h/.m` — Keychain read + `/api/oauth/usage` poll for the
  Fable weekly bar, from `VP/ClaudeOAuthUsage.swift`.
- `CodexUsageReader.h/.m` — `~/.codex/` reader, from `VP/CodexUsageReader.swift`.
- `NotchWindow.h/.m` — the pill shape, ring cells, tooltip card, content view
  and window controller, from `VP/NotchPillPath.swift` + `VP/Layout.swift` +
  `VP/ProviderCellView.swift` + `VP/TooltipCardView.swift` +
  `VP/NotchContentView.swift` + `VP/NotchWindowController.swift`.
- `AppDelegate.h/.m` + `main.m` — app entry point and the polling coordinator,
  from `VP/AppDelegate.swift` + `VP/main.swift` + `VP/UsageCoordinator.swift`.

Nine files instead of Swift's eighteen: Objective-C doesn't need Swift's
one-type-per-file granularity, and fewer files compile and link faster.

## The two review fixes (done during the port, not deferred)

1. **Stale readings are now shown as stale.** `ClaudeUsageFile` computed
   `isStale` but nothing consumed it in the Swift reference. In this port,
   `VPUsageCoordinator` passes `isStale` through to
   `VPNotchWindowController`, which:
   - dims the Claude ring's progress arc, glyph and percentage label
     (`VPProviderCellView.stale`), and
   - dims the affected row(s) in the hover card and appends
     "· desactualizado" to their "N % usado" text
     (`VPTooltipCardView.staleRowLabels`).
   The Fable row is excluded from this — it comes from its own live poll each
   time the card is shown, so it is never marked stale by the file's window.
2. **Thread-safe OAuth poll state.** `ClaudeOAuthUsage.swift` mutated
   `lastAttempt`/`backoffUntil`/`consecutive429` as unsynchronized `static
   var`s from a background `URLSession` callback. `VPClaudeOAuthUsage` now
   serializes every read and write of that state through a private serial
   `dispatch_queue_t` (`io.techbooster.codenotch-vp.claude-oauth-usage.state`),
   so the completion callback (delivered off the calling thread) can never
   race a concurrent `pollWithCompletion:` call.

## Build / run

```
mkdir -p "build-objc/Codenotch VP.app/Contents/MacOS" "build-objc/Codenotch VP.app/Contents/Resources"
clang -fobjc-arc -framework AppKit -framework CoreGraphics -framework Security \
  VP-ObjC/Palette.m VP-ObjC/Glyphs.m VP-ObjC/UsageModel.m \
  VP-ObjC/ClaudeUsageFile.m VP-ObjC/ClaudeOAuthUsage.m VP-ObjC/CodexUsageReader.m \
  VP-ObjC/NotchWindow.m VP-ObjC/AppDelegate.m VP-ObjC/main.m \
  -o "build-objc/Codenotch VP.app/Contents/MacOS/Codenotch VP"
cp VP-ObjC/../VP/Info.plist "build-objc/Codenotch VP.app/Contents/Info.plist"
codesign --force --deep -s - "build-objc/Codenotch VP.app"
open "build-objc/Codenotch VP.app"
```

To fast-check a single file without a full link (seconds, not minutes):
`clang -fsyntax-only -fobjc-arc -framework AppKit VP-ObjC/<File>.m`.

To install into `~/Applications` and load the LaunchAgent:
`VP-ObjC/Scripts/install-vp-objc.sh` (build first — it does not build for
you). It reuses the same LaunchAgent identity
(`io.techbooster.codenotch-vp`, same `~/Applications/Codenotch VP.app`
destination) as the Swift build's `Scripts/install-vp.sh` — only the
source tree it copies from differs (`build-objc/` vs `build/`).

## Wiring up the real 5h/weekly numbers (unchanged from the Swift version)

Nothing about this needs to change for the ObjC build: `ClaudeUsageFile`
reads the exact same `~/.claude/state/usage-5h.json` file, with the exact
same keys, on the exact same 15-second cadence as the Swift version did.

`Scripts/tb-usage-sink.js` (the sibling `Scripts/` folder at the repo root,
reused as-is — it's plain Node and entirely unaffected by the Swift/Command
Line Tools issue) is what keeps that file fresh: it reads the same JSON
Claude Code already feeds the status line on every refresh
(`rate_limits.five_hour` / `rate_limits.seven_day`) and writes it to
`~/.claude/state/usage-5h.json` atomically, keeping the existing
`used_percentage`/`resets_at`/`updated_at` keys `tb_usage_breaker.py`
depends on and only adding `seven_day` as a new sibling object.

To wire it in, point `~/.claude/settings.json`'s `statusLine` command at
`Scripts/tb-statusline-wrapper.sh` instead of the status line script
directly:

```
"command": "/Users/vasylpavlyuchok/Documents/TechBooster/own/codenotch/Scripts/tb-statusline-wrapper.sh"
```

That wrapper tees stdin to the sink and then execs the existing
`~/.claude/hooks/gsd-statusline.js` unchanged. As with the Swift version,
nothing in this repo edits `~/.claude/settings.json` automatically — that
one line is the CEO's call, documented here, not applied.

## The Fable bar and Codex — same behavior as the Swift version

Read-only Keychain access to the `Claude Code-credentials` item, the same
`GET https://api.anthropic.com/api/oauth/usage` request with the same
headers, the same "kind"/"scope.model.display_name" contains "fable" match,
the same 60s minimum poll interval and 429 backoff curve (60s, doubling,
capped at 15 minutes). Codex reads `~/.codex/auth.json` only if that folder
exists; on this Mac it does not, so the ring shows grey with "—" and the
card says "Codex no está instalado" — no data is invented.

## Known issue: repeated keychain password prompts (22-sep-2026)

Codenotch VP polls the `Claude Code-credentials` keychain item read-only
every 60s (`ClaudeOAuthUsage.m`, `readKeychainCredentialData`). It is not
the one causing the repeated "Codenotch VP wants to access key..." password
dialog you may see — three earlier fixes attacked the app itself (stable
code-signing identity, `security set-key-partition-list` on the *signing*
key, "Allow all applications" on the item's classic ACL, Hardened Runtime)
and each one held for a while, then the dialog came back anyway. Confirmed
root cause: the **`claude` CLI itself rewrites this same keychain item**
whenever it refreshes your OAuth token (confirmed by correlating the
item's `mdat` and a `security[pid]` keychain-commit log entry with the next
prompt, seconds later, each time). Rewriting the item's value resets its
classic ACL — including "Allow all applications" — regardless of what
Codenotch VP does. `kSecUseAuthenticationUIFail` (already set on the query,
line ~40 of `ClaudeOAuthUsage.m`) cannot suppress this: that flag only
silences Touch ID / passcode prompts on protected keys, not this "app wants
to access this generic-password item" ACL dialog — there is no code-side
flag that guarantees it stays silent.

**Fix**: run `VP-ObjC/Scripts/fix-keychain-partition-list.sh` once, on any
Mac, any time after install (safe to re-run). It sets a partition-list ACL
on the item instead of the classic per-app "trusted applications" list —
the same mechanism Homebrew/Docker/1Password use for exactly this class of
bug, because it is checked against the writer's code-signing identity
rather than a static list that gets discarded when the item is rewritten.
It will prompt for your login keychain password via the normal macOS
dialog — that is expected, not Codenotch nagging you.

If this ever needs re-diagnosing (e.g. it turns out the partition-list
approach also gets reset), don't re-guess blind — capture `log stream`
live filtered on the exact item/process, not `log show` after the fact;
that is what finally nailed this one down. Full incident history:
`decisions/log.md` in the `tb-os` repo, entries dated 17/18/22-sep-2026.

## What is out of scope (same as the Swift version's brief)

Mobile pairing, auto-update, 80%/100% notifications, Accessibility
permission, drag-to-move along the edge.
