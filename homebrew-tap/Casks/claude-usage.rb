cask "claude-usage" do
  version "0.1.0"
  sha256 "195a0016341bd85ea8c983ed2b5f39a78e51e0937b74ced316c501badf9a53c8"

  url "https://github.com/biks2013-tools/claude-usage/releases/download/v#{version}/Claude-Usage-#{version}.zip"
  name "Claude Usage"
  desc "Claude subscription usage and Claude Code sessions, in the menu bar and terminal"
  homepage "https://github.com/biks2013-tools/claude-usage"

  depends_on macos: :sonoma

  app "Claude Usage.app"
  binary "#{appdir}/Claude Usage.app/Contents/MacOS/ClaudeUsage", target: "claude-usage"

  uninstall quit: "com.giorgosmarinos.claude-usage"

  caveats <<~EOS
    Menu bar: open Claude Usage (gauge icon, no Dock icon). Usage is fetched only
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
