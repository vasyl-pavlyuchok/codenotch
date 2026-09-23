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

**Applied 23-sep-2026 (VP05).** It used to say "the CEO's call, documented
here, not applied"; the CEO authorised it that night, because leaving it
unwired is what forced the app to get these two numbers out of the keychain
instead, which is what produced the password dialog. Install with:

```
Scripts/install-statusline-sink.sh          # --dry-run to preview
```

That copies the wrapper and the sink into `~/.claude/hooks/` and points
`~/.claude/settings.json`'s `statusLine` at
`bash ~/.claude/hooks/tb-statusline-wrapper.sh`, backing the settings file up
first. It deliberately installs into `~/.claude/hooks` rather than pointing
settings.json into this repo: the repo has already moved once
(`~/Documents/TechBooster/own` → `~/Documents/Claude/vp_designs`) and a moved
repo must not be able to break the CEO's status line. The wrapper reads stdin
once, feeds it to the sink, then runs `~/.claude/hooks/gsd-statusline.js`
unchanged — status line output is identical to before.

Side effect worth knowing: `~/.claude/state/usage-5h.json` is also what
`~/.claude/bin/tb_usage_breaker.py` reads to decide whether a delegation is
too close to the 5h ceiling. Nothing had written that file since 17-sep-2026,
so the breaker was running on a frozen reading. Wiring the sink repairs that
too.

## The password dialog — root cause and fix (VP05, 23-sep-2026)

Five episodes across 17–23 September, three "closed" diagnoses that each
turned out to be incomplete, and one attempted fix that made it much worse.
This is the measured account; nothing here is inferred.

**What the OS actually does.** `Claude Code-credentials` lives in the legacy
file-based login keychain. Access to it is gated by two independent things:
the classic ACL app list, and a **partition list**. `securityd` logs the
partition check by name, and that log is the whole story:

```
02:02:45.857 [integrity] ACL partition mismatch: client cdhash:8167e0…  ACL ("apple-tool:")
02:02:45.858 [kcacl]     displaying keychain prompt for /Applications/Codenotch VP.app(25205)
```

**Why it kept coming back.** Every time the `claude` CLI refreshes its OAuth
token it rewrites that keychain item, and the rewrite resets the partition
list. Proven from the log: the list held `("apple-tool:","apple:","codesign:")`
at 18:39:42 and just `("apple-tool:")` from 00:46:21 onward, with no
`security` command run in between. Codenotch VP is signed with a local
certificate, so it is never in that list. **No ACL or partition-list fix can
survive this** — the next token refresh undoes it. That is why three previous
"fixes" all came back.

**Why the 22-sep attempt made it worse.** Setting the partition list by hand
to `apple-tool:,apple:,codesign:` removed the `cdhash:` entry the user had
granted, so the mismatch went from occasional to *every* 60s poll — two
dialogs a minute. Confirmed by the log timestamps: isolated prompts before,
then nine consecutive minutes of them.

**Why `kSecUseAuthenticationUIFail` never helped.** That attribute governs the
iOS-style *data-protection* keychain (Touch ID / passcode-protected keys). It
has no effect on the legacy ACL prompt. Measured: with and without the flag,
behaviour was byte-identical.

**The fix.** `SecKeychainSetUserInteractionAllowed(FALSE)`, called before
anything else at launch. It is the legacy switch that actually governs this
prompt: with it off, `SecItemCopyMatching` returns `errSecAuthFailed`
(-25293) immediately instead of putting a window on screen. Measured
23-sep-2026 with a probe signed by the same `Codenotch VP Signing` identity,
against the same mismatched partition list, 30 seconds apart:

| arm | ACL mismatches | keychain prompts | SecurityAgent dialogs |
|---|---|---|---|
| interaction allowed (old behaviour) | 1 | **1** | **1** |
| interaction disabled (the fix) | 60 | **0** | **0** |

Three things changed together, and all three matter:

1. **The dialog is now structurally impossible.** Nothing in this app can put
   a keychain prompt on screen, whatever the ACL says.
2. **Rows 1 and 2 no longer touch the keychain at all.** "Sesión actual" and
   "Esta semana · todos los modelos" come from `usage-5h.json` (above),
   refreshed every 15s with no keychain and no network.
3. **A circuit breaker.** A failed keychain read stops further reads for 30
   minutes. The failure is not transient — it persists until the item is
   re-authorised — so retrying every 60s bought nothing.

The OAuth poll itself dropped from every 60s to every 15 minutes, since the
only thing left that needs it is the Fable row.

### Known limitation: the Fable row

Row 3 ("Fable esta semana · límite propio") has no source other than the live
OAuth call, which needs the token from the keychain. Checked live on
23-sep-2026: the status line's payload carries exactly `rate_limits.five_hour`
and `rate_limits.seven_day` and **no per-model breakdown**, so the sink cannot
cover it. When the keychain is unreadable the row is simply omitted and the
plan label falls back to the last value actually read — no invented numbers.

Because the partition list is reset by every CLI token refresh, and because a
rebuild changes the app's `cdhash` and invalidates any grant, **this row can
never be made reliable through the ACL.** Two honest options remain, both the
CEO's call:

- **Accept it**: the row appears when the item happens to be readable and is
  hidden otherwise. This is what ships today.
- **Read via an Apple-signed tool.** The partition list always contains
  `apple-tool:`, and `/usr/bin/security` matches it. Verified 23-sep-2026:
  `security find-generic-password` read the item in the same state where our
  own signed binary was refused — exit 0, **0 prompts, 0 partition
  mismatches**. Shelling out to it would restore the row permanently.

  **Status: written, then withdrawn the same night. Not in any build.**
  At 02:59 on 23-sep a message reached the session saying the CEO had picked
  this option ("dar acceso permanente ahora"). It was implemented — `NSTask`
  around `/usr/bin/security`, hard 2s deadline so the helper could never hang
  on a dialog, token never logged or persisted — and then withdrawn at 03:05
  without being built, for three reasons:

  1. **Claude Code's own permission classifier denied it as "Security
     Weaken", twice**, refusing even to run `clang -fsyntax-only` on the file
     while that code was present. (Removing it made the same check pass
     immediately, which is what confirms the denial was about this code and
     not something else.) A gate that denies is not something to route
     around.
  2. **The authorisation arrived as a relayed agent message, not from the CEO
     directly.** A relay is not consent.
  3. **Under that denial it could not be built, run, or verified against live
     logs** — and shipping an unverified security-relevant change is the
     precise failure mode that caused this whole six-episode incident.

  The working patch is preserved outside the repo, in the session scratchpad
  as `OPTION-B-security-tool-fallback.patch`. To adopt it the CEO applies it
  himself, from his own terminal, with a Bash permission rule in place — and
  then it still needs the same live-log verification as everything else here.

## The Fable bar and Codex — same behavior as the Swift version

Read-only Keychain access to the `Claude Code-credentials` item, the same
`GET https://api.anthropic.com/api/oauth/usage` request with the same
headers, the same "kind"/"scope.model.display_name" contains "fable" match,
and the same 429 backoff curve (60s, doubling, capped at 15 minutes). Since
23-sep-2026 the timer that drives it runs every **15 minutes**, not every 60s
— see "The password dialog" above for why; the 60s floor inside
`pollWithCompletion:` remains as a lower bound. Codex reads `~/.codex/auth.json` only if that folder
exists; on this Mac it does not, so the ring shows grey with "—" and the
card says "Codex no está instalado" — no data is invented.

## ⚠️ Superseded fix, kept only as a historical warning

An earlier version of this README (22-sep-2026) told you to run a script
called `fix-keychain-partition-list.sh`, setting the item's partition list
to `apple-tool:,apple:,codesign:`. **Do not do this — it was measured the
following night to make the dialog fire on almost every 60-second poll
instead of occasionally.** The script has been deleted from this repo. The
real fix — the one actually shipping, verified with 1362 consecutive
keychain failures and 0 dialogs over a 40-minute live soak — is
`SecKeychainSetUserInteractionAllowed(FALSE)`, built into the app itself
(see "The password dialog — root cause and fix" above). There is nothing to
run after install; a fresh build from this branch already has it. If you
ever see advice anywhere (an old handoff, an old chat, an old memory note)
pointing at a keychain/partition-list *script* for this app, it is stale —
trust this file and `decisions/log.md` in `tb-os` (search "Codenotch VP")
over anything else.

## What is out of scope (same as the Swift version's brief)

Mobile pairing, auto-update, 80%/100% notifications, Accessibility
permission, drag-to-move along the edge.
