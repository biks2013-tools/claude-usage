# Claude Usage — Design

## Purpose

Show the Claude subscription's usage from the menu bar, on demand: limits (5-hour session, weekly,
weekly per model) with reset times, the week's split by product, extra usage and credits.

## Data source

There is no documented way for an app to read a subscription's limits (checked 2026-10-24: the
Claude Code docs expose per-run cost in `claude -p --output-format json`, not plan limits, reset
times, plan name or renewal date). The app uses the endpoint behind Claude Code's `/usage`:

- `GET https://api.anthropic.com/api/oauth/usage`
- `Authorization: Bearer <Claude Code access token>`, `anthropic-beta: oauth-2025-04-20`
- Answer (2026-10-24): `limits[]` (`kind` `session` / `weekly_all` / `weekly_scoped`, `percent`,
  `severity`, `resets_at`, `scope.model.display_name`), `seven_day_breakdown.rows[]`
  (`display_name`, `percent`), `extra_usage` (`is_enabled`, `monthly_limit`, `used_credits`,
  `currency`, `spend_limit_reached`), `spend.used` / `spend.limit` (`amount_minor`, `currency`,
  `exponent`), the older `five_hour` / `seven_day` objects (`utilization`, `resets_at`), and many
  null placeholder keys. No renewal date.

The plan name comes from the Keychain item's public fields: `subscriptionType` (`max`) and
`rateLimitTier` (`default_claude_max_20x`) give "Max 20x".

## Credentials

- Login Keychain, generic password, service `Claude Code-credentials`; its data is JSON
  `{"claudeAiOauth": {accessToken, refreshToken, expiresAt (ms), subscriptionType, rateLimitTier,
  scopes}}`.
- Read with `SecItemCopyMatching` on a background queue (the first read shows the Keychain prompt;
  *Always Allow* sticks while the app's signature stays the same, hence the stable Developer ID
  signing).
- Read fresh for every check (Claude Code renews the token on its own schedule), used for one
  request, then dropped. `Credentials.description` prints `<hidden>` for the token.
- Expired (`expiresAt` passed) or 401/403: "Claude Code's sign-in has expired — run claude once".
  The refresh token is never used: refreshing rotates it and would sign Claude Code out.

## Flow

1. `menuNeedsUpdate`: start a check unless one is running; build the menu from the last answer,
   with "Checking…" in the header (or "Asking Anthropic…" the first time).
2. `UsageClient.fetch`: Keychain → expiry check → request (10 s timeout) → `UsageReport.decode`.
3. On the answer (main queue): keep it with its time, or keep the error; if the menu is still
   open, rebuild it in place.

No timer, no background refresh, no network at launch.

## Decoding

`UsageCore.UsageReport` decodes every part optionally (`try?` per part), so a changed or unknown
part hides its rows instead of failing. `limits` falls back to the older `five_hour` / `seven_day`
objects when absent. Dates are ISO 8601 with or without fractional seconds; microseconds are
trimmed to milliseconds for `ISO8601DateFormatter`.

## Sessions

- **List:** `claude agents --json` (documented: active interactive and background sessions), run on
  every menu open on a serial queue (≈0.15 s), alongside the usage check. Decoded by
  `UsageCore.AgentSession` (`pid` only for interactive sessions; `status` for interactive, `state`
  for background). Sorted needs-you (blocked, waiting, anything unknown) → working (busy, running)
  → idle, newest first.
- **Tools:** `claude` from `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`,
  `~/.claude/local`; `tmux` from Homebrew or `/usr/bin`; the cmux CLI inside the cmux app bundle
  (`com.cmuxterm.app`, `Contents/Resources/bin/cmux`). Child processes get those folders on PATH
  and a 5 s time limit.
- **Navigate** (`Navigator`, off the main thread):
  1. Background session (no pid): `cmux new-workspace --name <name> --cwd <cwd> --command
     "claude attach <id>" --focus true`.
  2. Interactive: tty from `ps -o tty= -p <pid>`.
  3. A cmux terminal surface with that tty (`cmux tree --all --json`: windows → workspaces → panes
     → surfaces with `ref` and `tty`): `focus-window`, `select-workspace`, `focus-panel`, then
     activate cmux. The cmux socket accepts these from an app outside cmux (checked 2026-10-24).
  4. Else a tmux pane with that tty, searching every server socket in `$TMUX_TMPDIR` (default
     `/private/tmp`)`/tmux-<uid>/` (`list-panes -a`): `select-window`, `select-pane`; then the
     client attached to that session (`list-clients`): its cmux surface, else the app owning its
     terminal; with no client, a new cmux workspace running `tmux -S <socket> attach -t <session>`.
  5. Else activate the nearest ancestor process that is a regular app (the terminal).
  Apps are brought forward with `NSWorkspace.openApplication(activates: true)`, which works from a
  background app (this one, once its menu has closed).

## Going to another desktop (`DesktopSwitcher`)

macOS does not follow an app to a window on another desktop (and this Mac has "When switching to
an application, switch to a Space with open windows" off). Activating cmux, `focus-window` with
cmux active, and focusing the window with `_SLPSSetFrontProcessWithOptions` all left the desktop
unchanged (checked 2026-10-24). So, after the cmux focus commands:

1. Find the cmux window: Accessibility lists cmux's windows with the identifier
   `cmux.main.<window UUID>` (`cmux tree --json --id-format both` gives the UUID) and the window id
   (`_AXUIElementGetWindow`). Window titles are not available without Screen Recording (the window
   server and `CGWindowList` return none to an app without it), so titles are not used.
2. Its desktop: `SLSCopySpacesForWindows`. Already shown on its display: done.
3. Otherwise step that display to it with the user's "Move left/right a space" shortcut (symbolic
   hotkeys 79/81, default ⌃(fn)←/→), one desktop per press, the pointer warped to that display
   meanwhile and put back after; each step waits for the switch (50 ms checks of
   `SLSManagedDisplayGetCurrentSpace` / `IsAnimating`, at most 1.5 s). "Switch to Desktop N" was not
   used: on this Mac it did not reach the second display's desktops.
4. macOS lists an app's windows on hidden desktops only partly. If the window is not listed, the
   desktops of cmux's unlisted normal windows (from `CGWindowList`, which needs no permission for
   ids, bounds and layers) are visited in turn until Accessibility lists it.
5. Bring cmux forward and `focus-window` again, now that the window is on screen.

Without Accessibility, the app asks for it (system prompt) and says to choose the session again;
the tab is still selected in cmux.
  Failures show an alert with the reason.

## Menu

Header (plan, "Updated HH:mm" / "Checking…"); an error message when the last check failed;
**Plan limits** (one row per limit: title, percent, bar coloured accent / orange ≥ 75 % or a
non-normal severity / red ≥ 90 %, "Resets 09:00 · in 1 h 20 m"); **This week by product**;
**Beyond the plan** (extra usage, credits spent); Open Usage on claude.ai; Billing and Renewal
Date… (claude.ai billing page); Open at Login (`SMAppService.mainApp`); Quit.

## Command line (`CLI`)

One executable, two roles, so the Keychain's *Always Allow* (tied to the signature) covers both:
started by Launch Services (parent launchd, pid 1) with no arguments it is the menu bar app;
otherwise it runs a command and exits. The cask links
`Claude Usage.app/Contents/MacOS/ClaudeUsage` as `claude-usage`.

- `usage` (default): plan, one line per limit (title, percent coloured like the menu, a 20-cell
  bar, reset text), the week by product, extra usage and credits. `--json` prints Anthropic's
  answer as received.
- `sessions` / `ls`: numbered, sorted like the menu (activity, title, folder or "background").
  `--json` prints the sorted `AgentSession` list.
- `go <n|name|id>`: by number from `sessions`, exact title, session or short id prefix, then title
  substring; runs the same `Navigator` as the menu.
- Colours only on a terminal; errors to stderr; exit 1 on failure, 2 on bad usage.

## Icon

One mark, two renderings: a 270° usage gauge, two thirds full with a knob at the reading, around a
twelve-ray spark (eight in the menu bar).

- App icon: cream on a terracotta tile, drawn in code by `scripts/make-icon.swift` (Core Graphics,
  every size from 16 to 1024 px, packed with `iconutil`). The generated `Resources/AppIcon.icns`
  is committed; `build-app.sh` copies it into the bundle (`CFBundleIconFile`). Rerun the script
  after changing the drawing.
- Menu bar: `StatusIcon` draws the same mark at 18 pt as a template image (track at 35 % alpha,
  filled part opaque), so macOS tints it for light, dark and highlighted menu bars. It is fixed:
  it does not show the last reading, since that would go stale without polling.

## Release

`scripts/package.sh`: tests, universal build, Developer ID signature with hardened runtime,
notarized and stapled zip (`Claude-Usage-<version>.zip`), `SHA256SUMS`, and
`homebrew-tap/Casks/claude-usage.rb` (`app` + `binary … target: "claude-usage"`, `uninstall quit:`).
Published on GitHub `biks2013-tools/claude-usage` (public) with the tap
`biks2013-tools/homebrew-claude-usage`.

## Files

| File | Role |
|------|------|
| `Sources/UsageCore/Usage.swift` | The usage answer, tolerant decoding, ISO dates |
| `Sources/UsageCore/Credentials.swift` | Keychain JSON → token (hidden), expiry, plan name |
| `Sources/UsageCore/Format.swift` | Titles, levels, percent, reset and duration text, money |
| `Sources/ClaudeUsage/UsageClient.swift` | Keychain read, request, errors in plain words |
| `Sources/ClaudeUsage/StatusController.swift` | Status item, menu, row views |
| `Sources/ClaudeUsage/StatusIcon.swift` | Menu bar icon: the gauge-and-spark mark as a template image |
| `Sources/ClaudeUsage/main.swift` | Command or accessory app (no Dock icon) |
| `Sources/ClaudeUsage/CLI.swift` | The `claude-usage` command |
| `Sources/ClaudeUsage/Sessions.swift` | Running tools, the session list, `Navigator` |
| `Sources/ClaudeUsage/Desktops.swift` | Finding a window's desktop, switching with Mission Control |
| `scripts/package.sh` | Notarized release zip, checksums, Homebrew cask |
| `scripts/build-app.sh` | Universal release build, bundle, signing, install |
| `scripts/make-icon.swift` | Draws the app icon → `Resources/AppIcon.icns` (+ a 1024 px preview) |
