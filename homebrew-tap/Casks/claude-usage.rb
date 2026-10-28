cask "claude-usage" do
  version "0.1.3"
  sha256 "4abc1a8f41317d3e48cad1b799ff17223d356916b017d12d81015f673c530d31"

  url "https://github.com/biks2013-tools/claude-usage/releases/download/v#{version}/Claude-Usage-#{version}.zip"
  name "Claude Usage"
  desc "Claude subscription usage and Claude Code sessions, in the menu bar and terminal"
  homepage "https://github.com/biks2013-tools/claude-usage"

  depends_on macos: :sonoma

  app "Claude Usage.app"
  binary "#{appdir}/Claude Usage.app/Contents/MacOS/ClaudeUsage", target: "claude-usage"

  uninstall quit: "com.giorgosmarinos.claude-usage"

  caveats <<~EOS
    Menu bar: open Claude Usage (gauge-and-spark icon, no Dock icon). Usage is fetched only
    when you open the menu or run the command.

    Terminal:
      claude-usage              plan limits, resets, the week by product
      claude-usage sessions     open Claude Code sessions
      claude-usage go <n|name>  go to a session
      add --json for machine-readable output

    It reads Claude Code's sign-in from the Keychain through macOS's security tool,
    without a prompt. Going to a cmux window on another desktop needs Accessibility
    for Claude Usage once.
  EOS
end
