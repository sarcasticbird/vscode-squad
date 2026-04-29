# CodeSquad

CodeSquad is a macOS utility that monitors your Claude Code sessions across VS Code windows. It shows a floating panel with live status for each workspace — who's working, who needs attention, and who's idle.

1. A floating panel that displays a roster of VS Code workspaces with Claude Code status indicators
2. An HTTP hook server that receives real-time events from Claude Code
3. A process scanner that discovers active Claude sessions and reads their metadata

<img width="306" height="414" alt="image" src="https://github.com/user-attachments/assets/f2526a1d-5b4d-40c3-9937-4a0cdeac2d36" />


## Prerequisites

- macOS 14.0 or later
- Xcode 16.0 or later (for building from source)
- VS Code with Claude Code extension or CLI

## Installation

```bash
git clone git@github.com:sarcasticbird/vscode-squad.git
cd vscode-squad/CodeSquad
./scripts/install.sh
```

The install script will:
- Build CodeSquad in release mode
- Compile the asset catalog (app icon)
- Codesign the app bundle
- Install to `/Applications`
- Clear quarantine flags
- Register with Launch Services
- Launch the app

### Persistent Accessibility Permissions

By default, ad-hoc signing means macOS resets Accessibility permissions on each rebuild. To avoid this during development:

```bash
./scripts/create-cert.sh
./scripts/build.sh
```

This creates a self-signed `CodeSquad Dev` certificate in your login keychain. Subsequent builds will use it automatically.

### Gatekeeper Notice

Since CodeSquad is not notarized, macOS will quarantine it on first run. The install script handles this automatically, but if the app won't open:

```bash
xattr -cr /Applications/CodeSquad.app
```

Or: right-click the app in Finder → Open → click "Open" in the dialog.

## Usage

Once launched, CodeSquad will:
- Discover open VS Code windows via the Accessibility API
- Install webhook hooks into `~/.claude/settings.json`
- Scan for running Claude processes and read session metadata
- Display a floating panel anchored to the corner of your screen

### Panel

- **Green dot** — Claude is working
- **Orange dot** — Claude needs your attention
- **Cyan dot** — Claude is idle
- **Gray dot** — no active Claude session

Click a workspace card to bring that VS Code window to focus and dismiss the attention state.

### Accessibility Permission

CodeSquad requires Accessibility access to discover VS Code windows. Grant it when prompted:

System Settings → Privacy & Security → Accessibility → enable CodeSquad

### Hook Server

CodeSquad runs a local HTTP server on `127.0.0.1:9876` to receive Claude Code lifecycle events. Hooks are installed automatically into `~/.claude/settings.json` with a backup of your existing config.

## Development

```bash
cd CodeSquad

# Quick dev build + run
./build-app.sh
open .build/CodeSquad.app

# Or use the scripts/ workflow
./scripts/build.sh
open .build/CodeSquad.app
```

### Regenerating the App Icon

```bash
swift scripts/generate_logo.swift       # creates scripts/icon_source.png
python3 scripts/generate_icons.py       # resizes into AppIcon.appiconset
```

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

## How It Works

CodeSquad combines three discovery mechanisms:

- **Accessibility API** — enumerates VS Code windows via `AXUIElement`, watches for window create/destroy events via `AXObserver`, and tracks app lifecycle via `NSWorkspace` notifications
- **HTTP Hooks** — a local `NWListener` server receives `attention`, `working`, `stopped`, `session-start`, and `session-end` events from Claude Code, matching each event's `cwd` to a discovered workspace
- **Process Scanning** — polls running processes via Darwin APIs (`proc_listpids`, `proc_pidpath`) every 3 seconds, reads session metadata from `~/.claude/sessions/{pid}.json`, and extracts chat titles from `~/.claude/projects/` JSONL files

## Privacy

CodeSquad runs entirely on your machine — no data leaves localhost. It reads Claude Code session files (`~/.claude/sessions/`, `~/.claude/projects/`) to display chat titles (the first line of your prompt) in the floating panel. The HTTP hook server binds to `127.0.0.1` only and is not accessible from the network.

## License

MIT — see [LICENSE](LICENSE).
