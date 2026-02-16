# ClaudeUsageBar

A lightweight macOS menu bar app to track your Claude.ai usage in real-time.

## Features

- **Color-coded spark icon** — green (<70%), orange (70-90%), red (>90%)
- **Session + weekly usage** — progress bars with reset times
- **Pro plan support** — shows weekly Sonnet usage when available
- **Notifications** — alerts at 25%, 50%, 75%, 90% session usage
- **Auto-refresh** — updates every 5 minutes + refreshes on popover open
- **Keychain storage** — cookie stored securely in macOS Keychain (not a plist)
- **Menu bar only** — no Dock icon, stays out of your way

## Setup

### Build from source

```bash
git clone https://github.com/yourusername/claude-usage-bar.git
cd claude-usage-bar
./build.sh
open ClaudeUsageBar.app
```

Requires Xcode Command Line Tools (`xcode-select --install`).

### Get your session cookie

1. Go to [claude.ai/settings/usage](https://claude.ai/settings/usage)
2. Open DevTools (`⌘⌥I`) → Network tab
3. Refresh the page, click the `usage` request
4. Copy the full `Cookie` header value from Request Headers
5. Paste it in the app's cookie input

## Architecture

```
Sources/
├── App.swift            # Entry point, status bar + popover controller
├── UsageModel.swift     # API client, data model, notifications
├── PopoverView.swift    # SwiftUI popover UI
├── StatusBarIcon.swift  # Color-coded spark icon
└── KeychainHelper.swift # Secure cookie storage via macOS Keychain
```

## Security

Unlike similar tools that store your session cookie in UserDefaults (plaintext plist), this app uses the **macOS Keychain** — the same secure storage that Safari and other apps use for passwords.

Your cookie is only ever sent to `claude.ai` endpoints. No telemetry, no external servers.

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode Command Line Tools

## License

MIT
