#!/bin/zsh
# Generates the Xcode project, builds with automatic signing, and installs to ~/Applications.
set -euo pipefail
cd "${0:A:h}"

if [[ ! -f Config/Signing.local.xcconfig ]]; then
  echo "Missing Config/Signing.local.xcconfig — copy Config/Signing.local.xcconfig.example and set your team ID." >&2
  exit 1
fi

xcodegen generate --quiet
xcodebuild -project ClaudeUsage.xcodeproj -scheme ClaudeUsage -configuration Release \
  -derivedDataPath build -allowProvisioningUpdates -quiet build

APP="build/Build/Products/Release/Claude Usage.app"
pkill -x "Claude Usage" 2>/dev/null || true
rm -rf ~/Applications/"Claude Usage.app"
cp -R "$APP" ~/Applications/
open ~/Applications/"Claude Usage.app"
echo "✓ Installed. Right-click the desktop → Edit Widgets → search \"Claude Usage\"."
