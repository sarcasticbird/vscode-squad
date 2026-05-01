# CodeSquad

CodeSquad is a macOS utility that monitors your Claude Code sessions across VS Code windows. It shows a floating panel with live status for each workspace — who's working, who needs attention, and who's idle.

1. A floating panel that displays a roster of VS Code workspaces with Claude Code status indicators
2. An HTTP hook server that receives real-time events from Claude Code
3. A process scanner that discovers active Claude sessions and reads their metadata

<img width="306" height="414" alt="image" src="https://github.com/user-attachments/assets/f2526a1d-5b4d-40c3-9937-4a0cdeac2d36" />

## Prerequisites

- macOS 14.0 or later (Apple Silicon)
- VS Code with Claude Code extension or CLI

## Installation

### Download (recommended)

1. Download the latest `CodeSquad-*.zip` from [Releases](../../releases/latest)
2. Unzip and drag `CodeSquad.app` to `/Applications`
3. Clear the quarantine flag (required for unsigned apps):
   ```bash
   xattr -cr /Applications/CodeSquad.app
   ```
4. Launch CodeSquad
5. **Reload your VS Code window** so the extension activates:
   Cmd+Shift+P → "Reload Window"

### Build from source

**Requirements:**
- Xcode Command Line Tools (`xcode-select --install`)
- If the CLT-bundled Swift compiler is too old, install a newer toolchain via [swiftly](https://github.com/swiftlang/swiftly):
  ```bash
  curl -L https://swiftlang.github.io/swiftly/swiftly-install.sh | bash
  swiftly install latest
  ```
  CLT is still needed for the macOS SDK — swiftly only manages the Swift compiler.

```bash
git clone git@github.com:sarcasticbird/vscode-squad.git
cd vscode-squad/CodeSquad
./scripts/install.sh
```

The install script will:
- Build CodeSquad via `scripts/build.sh`
- Generate the app icon (via `actool` if Xcode is installed, or `iconutil` from CLT)
- Codesign the app bundle
- Install to `/Applications`
- Clear quarantine flags
- Register with Launch Services
- Launch the app

## Usage

Once launched, CodeSquad will:
- Install a shim extension into VS Code to discover open workspaces
- Install webhook hooks into `~/.claude/settings.json`
- Scan for running Claude processes and read session metadata
- Display a floating panel anchored to the corner of your screen

### Panel

- **Green dot** — Claude is working
- **Purple dot** — Claude needs permission
- **Orange dot** — Claude needs your attention
- **Cyan dot** — Claude is idle
- **Gray dot** — no active Claude session

Click a workspace card to bring that VS Code window to focus and dismiss the attention state.

### Hook Server

CodeSquad runs a local HTTP server on `127.0.0.1:9876` to receive Claude Code lifecycle events. Hooks are installed automatically into `~/.claude/settings.json` with a backup of your existing config.

## Development

```bash
cd CodeSquad
./scripts/build.sh
open .build/CodeSquad.app
```

**Scripts:**
- `scripts/build.sh` — compiles the Swift binary, assembles the `.app` bundle, generates the app icon, and codesigns
- `scripts/install.sh` — runs `build.sh`, then installs to `/Applications` and launches
- `scripts/create-cert.sh` — creates a self-signed dev certificate for persistent codesigning identity

**Release builds:**
```bash
BUILD_CONFIG=release ./scripts/build.sh
```

### Regenerating the App Icon

```bash
swift scripts/generate_logo.swift       # creates scripts/icon_source.png
python3 scripts/generate_icons.py       # resizes into AppIcon.appiconset (Xcode only)
```

The build script handles icon generation automatically — `generate_icons.py` is only needed to update the `.xcassets` catalog for Xcode-based builds.

## Troubleshooting

### "Waiting for VS Code..." or "Extension installed — reload VS Code"

CodeSquad installs a shim extension into VS Code on first launch. VS Code must be reloaded to activate it:

1. Open VS Code
2. Cmd+Shift+P → "Reload Window"
3. The CodeSquad panel should populate within a few seconds

### Gatekeeper blocks the app

Since CodeSquad is not notarized, macOS may quarantine it. Fix with:

```bash
xattr -cr /Applications/CodeSquad.app
```

Or: right-click the app in Finder → Open → click "Open" in the dialog.

## How It Works

CodeSquad combines three discovery mechanisms:

- **VS Code Extension** — a shim extension installed into `~/.vscode/extensions/` reports workspace identity (name, folder paths, remote authority) to CodeSquad via HTTP POST to `127.0.0.1:9876` on startup and every 10 seconds
- **HTTP Hooks** — a local `NWListener` server receives `attention`, `working`, `stopped`, `session-start`, and `session-end` events from Claude Code, matching each event's `cwd` to a discovered workspace
- **Process Scanning** — polls running processes via Darwin APIs (`proc_listpids`, `proc_pidpath`) every 3 seconds, reads session metadata from `~/.claude/sessions/{pid}.json`, and extracts chat titles from `~/.claude/projects/` JSONL files

## Privacy

CodeSquad runs entirely on your machine — no data leaves localhost. It reads Claude Code session files (`~/.claude/sessions/`, `~/.claude/projects/`) to display chat titles (the first line of your prompt) in the floating panel. The HTTP hook server binds to `127.0.0.1` only and is not accessible from the network.

## Uninstallation

```bash
# Remove app
killall "CodeSquad" 2>/dev/null || true
rm -rf /Applications/CodeSquad.app

# Remove persisted state
rm -rf ~/Library/Application\ Support/CodeSquad

# Remove hooks from Claude settings (optional — restore from backup)
# Backups are at ~/.claude/settings.json.backup.*
```

## License

MIT — see [LICENSE](LICENSE).
