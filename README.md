# SwiftHoppy

> **Attribution:** Development up to and including commit [`91c3a4d`](https://github.com/WHYBBE/SwiftHoppy/commit/91c3a4dc7033b77bbab169b0365d65c6e19de19a) (*Rename app to SwiftHoppy*) was completed with **GPT-5.4**.

A macOS desktop app built with **Swift + SwiftUI + Swift Package Manager** for managing SSH connection records and tracking Linux/Unix system info over time.

[中文文档](README.zh-CN.md)

## Features

- Add, edit, and delete SSH connection records
- Store host, port, username, display name, and notes
- Optional **local machine** entries (open a local terminal, read local system info)
- Append system snapshots (kernel, last update, uptime) manually or via SSH
- Fetch and store hardware info (OS name, architecture, CPU, cores, memory)
- Per-connection notes with manual or time-based sort
- Sidebar dividers and sort modes: manual, name, IP
- Hide sensitive details (e.g. IP) in the sidebar
- Open `ssh://` links with a preferred terminal app (or the system default)
- Import / export connections as JSON
- English / Chinese UI
- System / light / dark appearance
- Modern split layout: sidebar overview, connection detail, system history

## Requirements

- macOS 13 or later
- Swift 5.9+ (Xcode or Swift toolchain)

## Run

```bash
swift run
```

Or open `Package.swift` / `SwiftHoppy.xcodeproj` in Xcode and run the **SwiftHoppy** scheme.

## Open SSH in a preferred app

Connections are turned into `ssh://username@host:port` URLs:

- If a preferred app path is set, that app opens the URL
- Otherwise the system default handler is used

Works well with apps that support `ssh://`, such as Terminal, iTerm2, Termius, Warp, Kitty, Ghostty, and WezTerm.

Local entries open a terminal without SSH.

## Fetch system info over SSH

The app uses the system `/usr/bin/ssh` client:

| Field | Source |
|--------|--------|
| Kernel | `uname` |
| Last update | Common package-manager cache/log paths (apt, dnf, yum, zypper, pacman, apk, FreeBSD pkg, etc.) |
| Uptime | `/proc/uptime` or `uptime` when available |
| Hardware | OS, architecture, CPU model/cores, total memory |

Each fetch **appends** a timestamped history entry; old entries are kept. Keys, `ssh-agent`, and `~/.ssh/config` are preferred. If a password is required, macOS shows a graphical prompt; canceling aborts that fetch.

## Data location

| File | Path |
|------|------|
| Connections | `~/Library/Application Support/SwiftHoppy/connections.json` |
| Preferences (language, theme, terminal apps, etc.) | `~/Library/Application Support/SwiftHoppy/terminal-apps.json` |

## Project layout

```
Sources/
  SwiftHoppyApp.swift          # App entry, window & settings scene
  ContentView.swift            # Sidebar, detail, editors, settings UI
  SSHConnection.swift          # Connection, notes, system/hardware models
  SSHConnectionStore.swift     # Persistence, import/export
  AppPreferencesStore.swift    # Language, theme, sort, terminal discovery
  RemoteSystemInfoService.swift# Local & remote system/hardware fetch
Package.swift
SwiftHoppy.xcodeproj/
```

## License

[MIT](LICENSE) © 2026 0x574859
