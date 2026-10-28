#!/bin/zsh
# Build, sign, notarize and package Claude Usage for a GitHub release: a zip (used by
# the Homebrew cask), SHA256SUMS, and the cask for that version
# (homebrew-tap/Casks/claude-usage.rb), which also installs the `claude-usage` command.
#
# Required environment:
#   CLAUDE_USAGE_SIGN_IDENTITY  Developer ID Application identity, by SHA-1
#                               (2C7D6068C232BA74073D56085DDBB04E5F14DF30).
#   NOTARY_PROFILE              notarytool keychain profile (tiler-notary: the team's
#                               App Store Connect API key, shared with Tiler).
#
# Usage: CLAUDE_USAGE_SIGN_IDENTITY=… NOTARY_PROFILE=tiler-notary scripts/package.sh
# VERSION and BUILD come from scripts/build-app.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

VERSION="$(sed -n 's/^VERSION="\(.*\)"$/\1/p' scripts/build-app.sh)"
BUILD="$(sed -n 's/^BUILD="\(.*\)"$/\1/p' scripts/build-app.sh)"
APP="$ROOT/build.noindex/Claude Usage.app"
DIST="$ROOT/dist"
ZIP="$DIST/Claude-Usage-$VERSION.zip"
SUMS="$DIST/SHA256SUMS"
CASK="$ROOT/homebrew-tap/Casks/claude-usage.rb"

[[ -n "$VERSION" && -n "$BUILD" ]] || { echo "error: could not read VERSION / BUILD from scripts/build-app.sh" >&2; exit 1; }
[[ -n "${CLAUDE_USAGE_SIGN_IDENTITY:-}" ]] || { echo "error: CLAUDE_USAGE_SIGN_IDENTITY is not set (Developer ID Application SHA-1)" >&2; exit 1; }
[[ -n "${NOTARY_PROFILE:-}" ]] || { echo "error: NOTARY_PROFILE is not set (a release must be notarized)" >&2; exit 1; }

echo "=== Packaging Claude Usage $VERSION (build $BUILD) ==="

# 1. Tests: a release is never packaged from a red tree.
swift test

# 2. Build + sign.
scripts/build-app.sh

# 3. Developer ID with the hardened runtime.
codesign --verify --deep --strict --verbose=2 "$APP"
SIGNATURE="$(codesign -dvv "$APP" 2>&1)"
[[ "$SIGNATURE" == *"Authority=Developer ID Application"* ]] \
  || { echo "error: not signed with a Developer ID Application identity" >&2; exit 1; }
[[ "$SIGNATURE" =~ "flags=0x[0-9a-f]+\(runtime\)" ]] \
  || { echo "error: hardened runtime is not enabled" >&2; exit 1; }

# 4. Zip, notarize, staple, zip again.
mkdir -p "$DIST"
make_zip() { rm -f "$ZIP"; ditto -c -k --norsrc --keepParent "$APP" "$ZIP"; }
make_zip
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
make_zip
spctl --assess --type execute --verbose=2 "$APP"

# 5. Checksums.
SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
(cd "$DIST" && shasum -a 256 "$(basename "$ZIP")" > "$SUMS")

# 6. Homebrew cask (copied into biks2013-tools/homebrew-claude-usage on release).
mkdir -p "$(dirname "$CASK")"
cat > "$CASK" <<CASKEOF
cask "claude-usage" do
  version "$VERSION"
  sha256 "$SHA"

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
CASKEOF
echo "=== Done: $ZIP ($SHA) and $CASK ==="
