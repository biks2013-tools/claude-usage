cask "claude-usage" do
  version "0.1.2"
  sha256 "4e345d7f4bc85595e68eacdde6a24ebfaa2deb01afb75011a8694afd5d8a6f4c"

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

    The first check asks for Keychain access to "Claude Code-credentials" (Claude
    Code's sign-in): choose Always Allow. Going to a cmux window on another desktop
    needs Accessibility for Claude Usage once.
  EOS
end
