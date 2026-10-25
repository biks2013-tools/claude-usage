# Issues - Pending Items

## Pending

- **The usage endpoint is undocumented.** `api/oauth/usage` may change or disappear without
  notice. Decoding is tolerant (unknown parts hide rows); if it breaks, the menu says "Unexpected
  answer from Anthropic". Re-check the shape against Claude Code's `/usage` when that happens.
- **No renewal date.** Anthropic does not expose the subscription's renewal date to apps; the menu
  links to the claude.ai billing page instead.

- **Two navigation paths not run live.** Attaching to a detached tmux session (the M365Mail
  agents) and opening a background session with `claude attach` were not run, to avoid opening
  workspaces on the user's sessions; their cmux command (`new-workspace`) was checked with a
  throwaway workspace. Try one of each from the menu.

## Completed

- **2026-10-25 — No icon of its own.** The app had no icon (generic in Finder and Login Items) and
  the menu bar used a stock SF Symbol. Added a gauge-and-spark mark: the app icon drawn by
  `scripts/make-icon.swift` (`Resources/AppIcon.icns`) and the same mark as a template menu bar
  icon (`StatusIcon`). Released as 0.1.2.

- **2026-10-25 — `claude-usage --version` printed "dev" through Homebrew's symlink.** `Bundle.main`
  is not the app when the executable is reached through `/opt/homebrew/bin/claude-usage`; the version
  is now read from the bundle of the resolved executable. Released as 0.1.1. Also: newer Homebrew
  refuses casks from untrusted taps, so the install steps now include `brew trust`.

- **2026-10-25 — `claude-usage` command and Homebrew distribution.** Requested by the user: sign,
  build and publish, installable and usable as a shell command. The app's executable doubles as
  the command (linked by the cask). Checked: `usage`, `sessions`, both `--json` forms, and the
  error paths (missing argument and unknown command exit 2, no match exits 1). A test run without
  arguments from a non-terminal shell started a second menu bar copy; the app/command decision now
  uses the parent process (launchd = app) instead of whether stdout is a terminal.
- **2026-10-25 — "outlook-work" missing from the list.** Not a defect: its Claude Code process had
  exited (the cmux tab showed only a shell, retitled "resume-claude"); once restarted it was
  listed again.

- **2026-10-24 — Choosing a session in a cmux window on another desktop did nothing visible.**
  Reported by the user. Cause: the window was on another desktop, and macOS does not switch
  desktops when an app is activated (Space switching on activation is off on this Mac); in testing
  the target window was on the current desktop, so it worked. Also, `NSRunningApplication.activate`
  from a background app is unreliable on macOS 14. Fix: `DesktopSwitcher` finds the cmux window
  through Accessibility (identifier `cmux.main.<UUID>`), reads its desktop (SkyLight, read-only)
  and steps there with the user's Mission Control shortcuts; apps are brought forward with
  `NSWorkspace.openApplication`. Window titles were ruled out: without Screen Recording the window
  server returns none (probed from a separate app). Needs Accessibility once; not yet run live
  (waiting for the permission).

- **2026-10-24 — Claude Code sessions in the menu.** Requested by the user: list the open sessions
  on this Mac and go to one. List from `claude agents --json`; navigation through cmux (tty →
  surface), tmux (tty → pane, attached client or a new attaching workspace), `claude attach` for
  background sessions, or the terminal app. 14 unit tests pass. Checked live: the menu listed all
  10 sessions sorted needs-you / working / idle; choosing "tiler" switched cmux from the
  coding-agents window to the tiler window and workspace and brought cmux forward. Also: reset
  times now round to the nearest minute (the menu had shown 08:59 for a 09:00 reset).

- **2026-10-24 — First version.** Requested by the user: show the Claude subscription's status
  (session and weekly consumption, resets, everything available), fetched only when the menu is
  opened. Data source, placement and language decided with the user (undocumented endpoint with
  Claude Code's Keychain token; a separate app; Swift). 8 unit tests pass. Checked live: after
  the Keychain prompt (Always Allow), the menu showed Max 20x, session 15 %, week 11 %, Fable 0 %,
  the product split, extra usage off and credits 0.
