# Homebrew tap for Claude Usage

[Claude Usage](https://github.com/biks2013-tools/claude-usage) shows your Claude subscription's
usage (5-hour session and weekly limits, reset times, the week by product, extra usage) and your
open Claude Code sessions, in the macOS menu bar and as the `claude-usage` command.

```sh
brew tap biks2013-tools/claude-usage
brew trust biks2013-tools/claude-usage   # newer Homebrew asks you to trust third-party taps
brew install --cask claude-usage
```

Update with `brew upgrade --cask claude-usage`. macOS 14 or later; signed with Developer ID and
notarized by Apple.
