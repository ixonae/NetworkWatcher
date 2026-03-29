# Network Watcher

A macOS menu bar app that monitors your external IP address and alerts you when it doesn't match the expected range for your current network.

## What it does

Network Watcher periodically checks your external IP address and compares it against IP ranges you configure per network (WiFi SSID, Ethernet, etc.). If your IP falls outside the expected range, it shows an alert and changes the menu bar icon to indicate a mismatch.

This is useful if you want to make sure your VPN is active, or that your traffic is routing through the expected path on a given network.

## Features

- **Menu bar status icon** showing connection state at a glance (match, mismatch, VPN, unknown, no network)
- **Per-network IP rules** — configure allowed IP ranges (individual IPs or CIDR notation) for each WiFi network, Ethernet, USB, or Thunderbolt connection
- **VPN-aware** — mark networks as VPN to get a distinct shield icon when connected
- **Unconfigured network handling** — choose to alert or allow networks without configured IP ranges
- **Configurable check interval** — set how often the IP is verified (default: 60 seconds)
- **Custom IP lookup service** — use ipify, ifconfig.me, icanhazip.com, or any custom URL (with optional auth token)
- **Optional IP display** in the menu bar
- **Launch at login** support

## Requirements

- macOS 26.0+
- Location permission (required by macOS to read the current WiFi SSID)

## Building

```bash
xcodebuild build -scheme NetworkWatcher -configuration Release
```

## Running tests

```bash
xcodebuild test -scheme NetworkWatcher -destination 'platform=macOS'
```

## License

See [LICENSE](LICENSE) for details.
