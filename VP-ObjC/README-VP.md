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
clang -fobjc-arc -framework AppKit -framework CoreGraphics -framework Security -framework QuartzCore \
  VP-ObjC/Palette.m VP-ObjC/Glyphs.m VP-ObjC/UsageModel.m \
  VP-ObjC/ClaudeUsageFile.m VP-ObjC/ClaudeOAuthUsage.m VP-ObjC/CodexUsageReader.m \
  VP-ObjC/NotchWindow.m VP-ObjC/AppDelegate.m VP-ObjC/main.m \
  -o "build-objc/Codenotch VP.app/Contents/MacOS/Codenotch VP"
cp VP-ObjC/../VP/Info.plist "build-objc/Codenotch VP.app/Contents/Info.plist"
codesign --force --deep -s - "build-objc/Codenotch VP.app"
open "build-objc/Codenotch VP.app"
```

`-framework QuartzCore` added 29-sep-2026: missing from this command since it
was first written, even though `NotchWindow.m` has imported
`<QuartzCore/QuartzCore.h>` and used `CAMediaTimingFunction` since
`fdec045` (18-sep-2026). A link against a fresh output path fails with
`Undefined symbols ... _OBJC_CLASS_$_CAMediaTimingFunction` without it —
confirmed live while verifying the 29-sep fixes below. The already-installed
`/Applications/Codenotch VP.app` kept working regardless because nothing had
rebuilt it from scratch with this exact documented command since; anyone
who did (a clean checkout, a different Mac) would have hit the same link
error this session did.

To fast-check a single file without a full link (seconds, not minutes):
`clang -fsyntax-only -fobjc-arc -framework AppKit VP-ObjC/<File>.m`.

To install and load the LaunchAgent: `VP-ObjC/Scripts/install-vp-objc.sh`
(build first — it does not build for you). Installs to `/Applications`, not
`~/Applications` (CEO request, 18-sep-2026: could not find `~/Applications`
in Finder — it is hidden from the sidebar by default). It reuses the same
LaunchAgent identity (`io.techbooster.codenotch-vp`) as the Swift build's
`Scripts/install-vp.sh` — only the source tree it copies from differs
(`build-objc/` vs `build/`).

**Don't launch the built app directly (double-click / `open`) as a substitute
for the installer.** Found live, 29-sep-2026: doing that creates a SEPARATE
process under an ephemeral per-app launchd job (`application.io.techbooster.
codenotch-vp.<session>.<pid>`, visible in `launchctl list`), not the real
`io.techbooster.codenotch-vp` LaunchAgent job — even while that real job
shows as loaded. That stray instance's `stderr`/`stdout` go to `/dev/null`
instead of `/tmp/codenotch-vp.{err,out}.log` (the plist's
`StandardErrorPath`/`StandardOutPath` only apply to the job launchd itself
starts), so nothing it does is diagnosable, and if it crashes `KeepAlive`
does not revive it, because that key is only wired to the real job. Two
instances can end up running at once this way (one stray, one real),
overlapping the same pill. Always rebuild then re-run
`VP-ObjC/Scripts/install-vp-objc.sh`, which `launchctl unload`/`load`s the
real job — it replaces whatever was running under that job, but will not
touch a stray manually-opened instance, which must be quit separately
(`kill <pid>`, found via `ps aux | grep "Codenotch VP"`).

## Wiring up the real 5h/weekly numbers

`ClaudeUsageFile` reads the exact same `~/.claude/state/usage-5h.json` file,
with the exact same keys, on the exact same 15-second cadence as the Swift
version did — that part is unchanged. As of 29-sep-2026 it is no longer the
ONLY source it reads; see "Two sources for rows 1/2" below for why.

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

### Two sources for rows 1/2 (29-sep-2026, CEO-reported)

Rows 1 and 2 had gone stale again — `usage-5h.json` frozen since 26-sep-2026,
three days, with no crash and no wiring change. Measured before touching
anything: `settings.json`'s `statusLine` still pointed at the wrapper, the
wrapper and `tb-usage-sink.js` were unchanged since 23-sep, and feeding the
sink a synthetic status-line JSON by hand wrote a fresh file instantly. So
the sink was never broken — **nothing was calling it with real data**.

Root cause: `tb-usage-sink.js` only runs when the *terminal* `claude` CLI
renders its status line (that's what invokes `statusLine`'s configured
command). The CEO had stopped using the terminal CLI in favour of the Claude
desktop app days before the file went stale — exactly when it stopped
updating. The desktop app has no reason to shell out to a terminal-only
status line hook, so nothing was ever going to call the sink again while
that held.

The fix is not "make the desktop app call the hook" — it is a second,
independent source: the desktop app writes its OWN usage log at
`~/Library/Application Support/Claude/plan-usage-history.json`
(`{version, samples: [{t, org, u: {fh, sd}}, ...]}`, `t` epoch-ms, `fh`/`sd`
the same 0-100 `five_hour`/`seven_day` percentages, appended roughly every
15 minutes whenever that app runs). Confirmed live, 29-sep-2026: the file's
mtime advanced in real time during this exact investigation, independently
of any terminal session. `ClaudeUsageFile.readWithNow:` now reads both files
and keeps whichever has the more recent `updatedAt`
(`readStatuslineSink`/`readDesktopAppHistory`, merged in `readWithNow:`), so
rows 1/2 stay live regardless of which client is actually running. Neither
source carries a per-model breakdown (both checked live) — samples from the
desktop app have no `resets_at` either, so a reading built from it leaves
that field `nil` (no reset-time line for that row) rather than inventing one.
Verified read-only against the real files on this Mac: with the sink's file
at `22:14:07Z` and the desktop app's at `22:19:37Z`, `readWithNow:` picked
the `22:19:37Z` reading and reported `isStale = NO`.

This also means: if the CEO goes back to using the terminal CLI, rows 1/2
keep working exactly as before (sink wins whenever it's the fresher one) —
this is additive, not a replacement.

### Fable row survives a restart now (29-sep-2026, CEO-reported)

CEO-reported: "he consumido Fable y no lo refleja" — and separately, the row
had gone missing outright after an app relaunch. Two different bugs, same
row:

1. **The keychain/`/usr/bin/security` read genuinely is flaky right now**,
   independent of anything in this app — reproduced live while
   investigating: a direct `/usr/bin/security find-generic-password` read
   (same command `+readCredentialViaSecurityTool` runs) came back empty in
   the same window the app's own log shows `deadline exceeded, killed` and
   `keychain read failed (OSStatus -25293)`. This is the same documented
   partition-list fragility as "The password dialog" below — not new, not
   fixed by this change, and not something this app can fix from its side
   (see that section for why no ACL/partition tinkering survives the next
   CLI token refresh).
2. **What WAS this app's own bug**: `oauthRows` (`AppDelegate.m`) held the
   Fable row only in memory, starting at `@[]` on every launch. A relaunch —
   or the routine flakiness in (1) landing right after one — wiped the row
   completely until the next lucky poll, which reads as "it forgot my Fable
   usage" even though the number itself was never wrong. The plan label
   (`+planLabel`) already persisted to `NSUserDefaults` for exactly this
   reason; the same treatment had never been extended to the Fable
   percentage itself.

Fixed: `VPClaudeOAuthUsage` now persists the last successfully-read Fable row
(`+rememberFableRow:`, called every time `pollWithCompletion:` actually finds
one) to `NSUserDefaults`, the same mechanism as `+planLabel`
(`+cachedFableRow`, `+cachedFableRowIsStale` — stale after the same 30-min
window `ClaudeUsageFile` uses). `VPUsageCoordinator` seeds `oauthRows` from
that cache at construction instead of starting empty, and a poll that
succeeds but happens not to include a `weekly_scoped`/Fable entry that round
merges by label (`-mergeOAuthRows:`) instead of replacing the whole array —
the old full-replace would have silently dropped a cached or previously-live
Fable row the moment one ordinary poll came back with only session/
weekly_all. A cached row older than 30 minutes is added to the same
`staleLabels` set the session/weekly rows use, so it renders dimmed with
"· desactualizado" instead of looking current. Verified with a standalone
harness exercising `+rememberFableRow:`/`+cachedFableRow`/
`+cachedFableRowIsStale` directly (9 checks, all passing) — deterministic,
independent of the live keychain's documented flakiness.

**Root cause of the missing row, found later the same day**: the CLI was
logged out. `claude auth status` said `loggedIn: false` and the keychain item
held `accessToken: ""`, `expiresAt: 0`, so the OAuth call had nothing to send.
`~/.local/bin/claude auth login` refilled it (via `Scripts/claude-login.sh`,
which bypasses the `tb-claude` shell wrapper that injects `--channels`), and
the row came back at 69%, matching the Claude desktop app's Uso panel.

**A `claude setup-token` token does not work here.** It is inference-only:
`/api/oauth/usage` answers HTTP 403 to it. `ClaudeOAuthUsage.m` still reads
`~/.claude/state/codenotch-token` (see `Scripts/save-token.sh`), but only when
the keychain holds no token, and logs the 403 once. Nothing needs that file.
The docs do not say how to revoke such a token server-side.

**What this does not fix**: if the keychain read has never once succeeded
since the CEO's last login/token-refresh, there is nothing to cache yet and
the row is still omitted — same as before. This change makes a real reading
survive restarts and transient failures; it cannot invent a number that was
never read.

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

### The Fable row (VP06, 24-sep-2026)

Row 3 ("Fable esta semana · límite propio") has no source other than the live
OAuth call, which needs the token from the keychain. Re-checked against the
official status-line schema on 24-sep-2026: the payload carries exactly
`rate_limits.five_hour`, `rate_limits.seven_day` and `rate_limits.spend_limit`
and **no per-model breakdown**, so the sink cannot cover it.

Because the partition list is reset by every CLI token refresh, and because a
rebuild changes the app's `cdhash` and invalidates any grant, **this row can
never be made reliable through the ACL.** From 24-sep-2026 it is read through
an Apple-signed tool instead:

- **Primary path — `/usr/bin/security`.** The partition list always contains
  `apple-tool:`, and `/usr/bin/security` matches it. Verified 23-sep-2026:
  `security find-generic-password` read the item in the same state where our
  own signed binary was refused — exit 0, **0 prompts, 0 partition
  mismatches**. `ClaudeOAuthUsage.m` (`+readCredentialViaSecurityTool`) runs it
  through `NSTask` with stdin on `/dev/null` (so it can never prompt), a hard
  2-second deadline followed by `SIGKILL`, stdout drained off-thread, and logs
  that carry only a byte count or an exit status — never the secret. It is
  tried on every poll (the poll is already throttled to 15 minutes).
- **Fallback — Keychain API.** If the helper fails or times out, the pre-VP06
  `SecItemCopyMatching` read runs unchanged, with its 30-minute breaker and
  user interaction disabled. When both fail the row is omitted and the plan
  label keeps its last real value — no invented numbers.

**History.** This exact design was written on 23-sep-2026 and withdrawn the
same night: Claude Code's permission classifier denied it as "Security
Weaken", the authorisation had arrived as a relayed agent message, and it
could not be verified under that denial. On 24-sep-2026 the CEO (Vasyl)
decided it **directly in session**, twice, after a fresh diagnosis showed the
row had been silently dead since the keychain dialog was disabled (log:
`keychain read failed (OSStatus -25293)` every 30 minutes, securityd:
`CSSMERR_CSP_OPERATION_AUTH_DENIED`). Task VP06. Verification after each
build: `/tmp/codenotch-vp.err.log` must show `security tool path: ok (N bytes)`
and the card must show three rows.

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
