# Claude Usage Widget

A native macOS desktop widget (small, medium, large) and menu bar app that shows your Claude plan usage: current session, weekly limits, and extra-usage spend.

## How it works

- **Menu bar app** reads the OAuth login Claude Code already stores in your Keychain and polls the same usage endpoint `/usage` uses. Interval is adjustable from the menu (1–60 min, default 5).
- **Widget** reads the latest snapshot from a shared App Group container. It can't fetch on its own because widgets are sandboxed and refresh-throttled by macOS.

The token is only read at runtime and never written to disk by this app.

## Requirements

- macOS 14+, Xcode, an Apple Development signing certificate
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- Claude Code installed and signed in

## Build

```sh
cp Config/Signing.local.xcconfig.example Config/Signing.local.xcconfig
# edit it: set DEVELOPMENT_TEAM and BUNDLE_ID_PREFIX
./build.sh
```

This generates the Xcode project, builds with automatic signing, installs to `~/Applications`, and launches the app. Then right-click the desktop → **Edit Widgets** → search "Claude Usage".

## Notes

- The login token expires after a few hours; Claude Code renews it whenever you use it. If it's stale, the widget keeps the last numbers and shows a ⚠️.
- The usage endpoint is undocumented and may change. Parsing lives in `App/UsageClient.swift`.
