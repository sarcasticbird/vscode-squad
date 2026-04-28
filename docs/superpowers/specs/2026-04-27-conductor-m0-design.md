# Conductor M0 Design Spec

A native macOS app (Swift 6, AppKit + SwiftUI) that surfaces Claude Code session state across multiple VS Code windows. Floating edge-docked panel with badge awareness and click-to-focus.

This is the M0 build — scoped to validate the core concept before investing in polish.

---

## Decisions

These were resolved during brainstorming and override the PRD where they differ:

- **Swift instead of Hammerspoon.** The Lua prototype already validated that AX discovery and HTTP hooks work. M0 builds the real app directly.
- **No hotkeys in M0.** Global Cmd+1..9 conflicts with VS Code editor group switching. Deferred until we can implement context-sensitive activation.
- **Focus only.** `AXUIElementPerformAction(kAXRaiseAction)` + `NSRunningApplication.activate()` — no window positioning. Default macOS Space-switching behavior.
- **Snap transitions.** Collapsed/expanded states switch instantly. No animation budget in M0.
- **Badge count on pill.** The collapsed pill shows a numeric count of pending badges, not just a dot. Pill width is 32–40px to keep the number readable.
- **~200ms hover dwell.** Prevents accidental expansion when the cursor sweeps past the screen edge.
- **No headless sessions.** Only VS Code windows are tracked. Terminal-only Claude sessions are out of scope.

---

## Architecture

Single-process macOS app. Three internal components, no cloud, no daemon.

### 1. WindowDiscovery

Owns the roster of VS Code workspaces.

**Startup scan:**
1. Filter `NSWorkspace.shared.runningApplications` by bundle ID: `com.microsoft.VSCode`, `com.microsoft.VSCodeInsiders`, `com.todesktop.230313mzl4w4u92` (Cursor).
2. For each matching PID, create `AXUIElementCreateApplication(pid)`.
3. Walk `kAXWindowsAttribute`. Filter to standard windows (skip floating palettes, sheets).
4. Read `kAXTitleAttribute` to extract workspace name.

**Workspace name extraction:**
VS Code titles follow `file.txt — my-project` or `my-project — Visual Studio Code`. Strip the app suffix, take the segment after the em-dash.

**CWD matching (for hook integration):**
Claude Code hooks POST an absolute `cwd` path. AX only gives us the window title (folder basename). Two strategies:
- **Basename match:** Last path component of `cwd` matched against parsed workspace name. Covers most cases.
- **Ambiguity fallback:** If two workspaces share a basename, check if any workspace name appears as a substring of the full `cwd`. Log a warning when ambiguous.

**Live updates:**
- `AXObserver` per VS Code PID, subscribed to `kAXWindowCreatedNotification` and `kAXUIElementDestroyedNotification`. Re-scan that app's windows on event.
- `NSWorkspace` notifications for app launch/terminate to pick up new VS Code instances or drop dead ones.
- Safety-net full rescan every 5 seconds to catch dropped observer events.

**Roster ordering:** Alphabetical by workspace name, stable across refreshes.

### 2. HookServer

Embedded HTTP server for Claude Code badge state.

**Server:** `NWListener` on `127.0.0.1:9876`, TCP, HTTP/1.1. No TLS (localhost-only). Manual HTTP parsing — two routes, no framework dependency.

**Routes:**
- `POST /notify` — Sets badge for the matching workspace. Fired by Claude Code on Notification events (permission prompts, idle prompts, auth dialogs, elicitations). Records `lastBadgedAt` timestamp.
- `POST /stop` — Clears badge for the matching workspace. Fired when a Claude Code session turn completes. Rationale: if Claude finished, it's no longer waiting — urgency is gone. A new `/notify` fires if it needs you again.

**Payload:** JSON with at minimum `cwd` and `session_id`. Parse loosely — extract known fields, ignore unknown. Return 400 on malformed body or missing `cwd`. Don't crash.

**Hook installation:**
On first launch, check `~/.claude/settings.json` for hook entries. If missing, offer to install:
```json
{
  "hooks": {
    "Notification": [
      { "hooks": [{ "type": "http", "url": "http://127.0.0.1:9876/notify" }] }
    ],
    "Stop": [
      { "hooks": [{ "type": "http", "url": "http://127.0.0.1:9876/stop" }] }
    ]
  }
}
```
Back up existing config to `~/.claude/settings.json.backup.<timestamp>` before writing.

### 3. Panel

Floating edge-docked UI surface.

**Window setup (`NSPanel`):**
- `.floating` window level
- `.canJoinAllSpaces` + `.stationary` collection behaviors
- `.nonactivatingPanel` style mask (clicking doesn't steal focus from VS Code)
- Transparent background, no title bar
- Default position: right edge of main display, vertically centered
- Draggable to reposition; position persists across launches

**Collapsed state (default):**
- 32–40px wide, ~80px tall pill
- Shows badge count when badges are active; subtle presence indicator when idle
- Semi-transparent dark background, low visual weight

**Expanded state:**
- Triggered by: any badge becoming active, OR mouse hover with ~200ms dwell delay
- Snaps to ~220px wide, tall enough for roster
- One row per workspace: folder name, truncated title subtitle, orange badge dot if active
- Badged rows get warm highlight (orange tint)
- Click a row → `AXUIElementPerformAction(kAXRaiseAction)` + `NSRunningApplication.activate()` → clear badge

**Collapse logic:**
- Last badge clears AND mouse outside panel → collapse after 300ms
- Mouse hovering → stay expanded regardless of badge state
- Mouse exit + no badges → collapse after 300ms

**Rendering:** SwiftUI via `NSHostingView`. AppKit owns the window; SwiftUI owns the pixels inside.

---

## State Management

### Runtime — single ObservableObject

`ConductorState` class with `@Published` properties:

| Property | Type | Written by |
|---|---|---|
| `workspaces` | `[Workspace]` | WindowDiscovery |
| `badges` | `[String: Bool]` | HookServer |
| `badgeCount` | `Int` (derived) | — |
| `lastBadgedWorkspace` | `String?` | HookServer |
| `panelExpanded` | `Bool` | Panel |
| `mouseInside` | `Bool` | Panel |

Each `Workspace` holds: `AXUIElement` reference, parsed workspace name, window title, owning app PID.

### Persisted — JSON file

`~/Library/Application Support/Conductor/state.json`:
- Panel position (x, y)
- Panel edge (right/left)
- Hook installation status

Read on launch, written on change (debounced). No database, no Core Data.

---

## Deferred from M0

| Feature | Reason |
|---|---|
| Hotkeys (Cmd+1..9, Cmd+0) | Global key conflicts with VS Code |
| Smooth animation | Snap transitions validate the concept |
| Headless sessions | Complexity without clear M0 value |
| Cursor/JetBrains support | Same AX mechanism, trivial addition post-M0 |
| Inline transcript preview | V2 per PRD |
| Layout snapshots | V2 per PRD |
| CLI | V2 per PRD |
| Multi-display docking | Default to main display |
| Onboarding tour | Hook install screen is sufficient; single user |
| Configurable delays | Hardcode 200ms dwell / 300ms collapse |

---

## Success Criteria

After two weeks of daily use with 4+ VS Code windows and Claude Code running in each:

1. Does the panel let you respond to permission prompts faster than cycling through windows?
2. Does the collapsed pill stay out of the way during deep work?

Both yes → proceed to polish and beta features. Either no → diagnose before adding scope.

---

## Reference

- **PRD:** `.claude/specs/conductor-prd.md` — full product requirements and v2 roadmap
- **Hammerspoon prototype:** `.claude/specs/conductor.lua` — original Lua proof of concept
- **ConAir project:** `~/Projects/ConAir` — reference for AppKit floating panel patterns, NSPanel setup, ObservableObject state management, NSApplicationDelegateAdaptor bridging
