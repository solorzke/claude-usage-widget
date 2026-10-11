# Claude Usage Widget

A native macOS desktop widget (small, medium, large) and menu bar app that shows your Claude plan usage: current session, weekly limits, and extra-usage spend. It refreshes on an interval you choose.

> Unofficial and not affiliated with Anthropic. It reads the same usage data Claude Code's `/usage` command shows.

## How it works

- **Menu bar app** reads the login Claude Code already stores in your Keychain and checks your usage every few minutes (1–60 min, default 5, adjustable from the menu).
- **Widget** shows the latest result. Widgets on macOS are sandboxed and refresh-throttled, so the menu bar app does the fetching and hands the data to the widget through a shared App Group container.

Your login token is read from the Keychain at runtime only. It is never written to disk or sent anywhere except Anthropic's API.

## Requirements

- macOS 14 (Sonoma) or later
- **Xcode**, signed in with an Apple ID (Xcode → Settings → Accounts). A free account works.
- **XcodeGen**: `brew install xcodegen`
- **Claude Code** installed and signed in with a Claude subscription (run `claude` once and log in)

## Install

1. **Clone the repo**

   ```sh
   git clone https://github.com/solorzke/claude-usage-widget.git
   cd claude-usage-widget
   ```

2. **Add your signing settings**

   ```sh
   cp Config/Signing.local.xcconfig.example Config/Signing.local.xcconfig
   ```

   Edit `Config/Signing.local.xcconfig`:

   - `DEVELOPMENT_TEAM`: your 10-character Apple team ID. Find it in Xcode → Settings → Accounts → select your team, or run:
     ```sh
     security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject
     ```
     and copy the `OU=` value.
   - `BUNDLE_ID_PREFIX`: any reverse-DNS prefix you own or make up, e.g. `com.yourname`.

   This file is git-ignored, so your values stay local.

3. **Build and install**

   ```sh
   ./build.sh
   ```

   This generates the Xcode project, builds with automatic signing, copies **Claude Usage.app** to `~/Applications`, and launches it. A gauge icon appears in your menu bar.

4. **Add the widget**

   Right-click the desktop → **Edit Widgets…** → search **"Claude Usage"** → drag the small, medium, or large size onto your desktop (or into Notification Center).

## Using it

Click the gauge icon in the menu bar to:

- see every limit with its reset countdown
- refresh now
- change **Check every** (1, 2, 5, 10, 15, 30, or 60 minutes)
- show or hide the session % next to the icon
- turn on **Launch at login**

## Troubleshooting

- **Widget doesn't appear in the gallery.** Make sure the app has been launched at least once, then restart the widget service and reopen the gallery:
  ```sh
  killall chronod
  ```
- **⚠️ "Login token expired"**: Claude Code's login token lasts a few hours and is renewed whenever you use Claude Code. Open Claude Code (run any command) and the widget recovers on the next check. The widget keeps showing the last known numbers in the meantime.
- **"No Claude Code login found"**: run `claude` and sign in.
- **Widget updates less often than the interval you set.** macOS rations widget refreshes; very short intervals (1–2 min) may be coalesced. The menu bar always shows the latest numbers.
- **Numbers look wrong or the widget breaks after an update.** The usage endpoint is undocumented and may change. Parsing lives in `App/UsageClient.swift`.

## Uninstall

1. Quit **Claude Usage** from its menu bar menu.
2. Remove the widget from your desktop.
3. Delete the app and its data:
   ```sh
   rm -rf ~/Applications/"Claude Usage.app"
   rm -rf ~/Library/Group\ Containers/*.ClaudeUsage
   ```

## Project layout

| Path | What it is |
| --- | --- |
| `App/` | Menu bar app: polling, Keychain read, settings UI |
| `Widget/` | WidgetKit extension: small / medium / large layouts |
| `Shared/` | Snapshot model and views used by both |
| `Config/` | Signing settings (`Signing.local.xcconfig` is yours and git-ignored) |
| `project.yml` | XcodeGen spec; the `.xcodeproj` is generated from it |
| `build.sh` | Generate, build, sign, install, launch |

## License

MIT. See [LICENSE](LICENSE).
