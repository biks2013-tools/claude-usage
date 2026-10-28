#!/bin/zsh
# Build Claude Usage.app (release, universal), sign it, and optionally install it.
#
#   CLAUDE_USAGE_SIGN_IDENTITY=<identity or SHA-1> scripts/build-app.sh [--install]
#
# The signing identity is required. A stable certificate (the Developer ID
# Application one) keeps the code signature stable across rebuilds, so the
# Keychain's "Always Allow" for Claude Code's sign-in keeps working; an ad-hoc
# signature would bring the Keychain prompt back after every build.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${CLAUDE_USAGE_SIGN_IDENTITY:-}" ]]; then
  echo "error: CLAUDE_USAGE_SIGN_IDENTITY is not set. Available identities:" >&2
  security find-identity -v -p codesigning >&2
  exit 1
fi

VERSION="0.1.3"
BUILD="4"
APP="build.noindex/Claude Usage.app"   # .noindex: Spotlight and Launchpad skip it

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/ClaudeUsage"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ClaudeUsage"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"   # drawn by scripts/make-icon.swift
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.giorgosmarinos.claude-usage</string>
  <key>CFBundleName</key><string>Claude Usage</string>
  <key>CFBundleDisplayName</key><string>Claude Usage</string>
  <key>CFBundleExecutable</key><string>ClaudeUsage</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>© 2026 Giorgos Marinos</string>
</dict>
</plist>
PLIST
codesign --force --options runtime --timestamp --sign "$CLAUDE_USAGE_SIGN_IDENTITY" "$APP"
codesign --verify --strict "$APP"
echo "built $APP"

if [[ "${1:-}" == "--install" ]]; then
  osascript -e 'tell application id "com.giorgosmarinos.claude-usage" to quit' 2>/dev/null || true
  sleep 1
  rm -rf "/Applications/Claude Usage.app"
  ditto "$APP" "/Applications/Claude Usage.app"
  open "/Applications/Claude Usage.app"
  echo "installed /Applications/Claude Usage.app"
fi
