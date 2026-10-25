# Claude Usage — Functions

| # | Function | Status |
|---|----------|--------|
| F1 | Menu bar icon; opening the menu checks usage (no polling, no network otherwise). | Done |
| F2 | Plan name from Claude Code's Keychain item (`subscriptionType` + `rateLimitTier`). | Done, unit-tested |
| F3 | Plan limits: 5-hour session, weekly (all models), weekly per model, each with percent, bar (accent / orange / red) and reset time with countdown. | Done, unit-tested |
| F4 | This week by product (Claude Code, chats, Cowork, other). | Done, unit-tested |
| F5 | Extra usage (off / spend this month / limit reached) and credits spent. | Done, unit-tested |
| F6 | Plain-language errors: not signed in, Keychain refused, sign-in expired (never refreshed by the app), HTTP error, network error, unknown format. | Done |
| F7 | Links to the claude.ai usage and billing pages (the renewal date is only there). | Done |
| F8 | Open at Login toggle (`SMAppService`). | Done |
| F9 | List the open Claude Code sessions (`claude agents --json`) with folder and activity, needs-you first, coloured dot. | Done, unit-tested, checked live |
| F10 | Go to a session in a cmux tab (window, workspace and tab come forward). | Done, unit-tested (tree parsing), checked live |
| F11 | Go to a session in a tmux pane (select it; bring the attached terminal forward, or attach in a new cmux workspace). | Done, unit-tested (parsing); not run live |
| F12 | Open a background session in a new cmux workspace (`claude attach`). | Done; cmux command checked, attach not run live |
| F14 | `claude-usage` command: `usage` (default), `sessions`, `go <n|name|id>`, `--json`, `--version`. | Done, checked live |
| F15 | Distribution: notarized zip on GitHub releases, Homebrew cask in `biks2013-tools/homebrew-claude-usage` installing the app and the command. | Done |
| F13 | Reset times shown to the nearest minute (Anthropic sends 05:59:59.9). | Done, unit-tested |
| F16 | Own icon: gauge-and-spark mark as the app icon (`AppIcon.icns`) and as a template menu bar icon. | Done |
