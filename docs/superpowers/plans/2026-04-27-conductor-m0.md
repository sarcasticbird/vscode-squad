# Conductor M0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS app that surfaces Claude Code session state across VS Code windows — floating edge-docked panel with badge awareness and click-to-focus.

**Architecture:** Single-process Swift 6 app with AppKit shell (NSPanel) + SwiftUI content. Three components — WindowDiscovery (AXUIElement), HookServer (Network.framework), Panel (NSPanel + SwiftUI) — connected through a shared ObservableObject state. Xcode project, no external dependencies.

**Tech Stack:** Swift 6, AppKit, SwiftUI, Network.framework, Accessibility APIs (AXUIElement)

**Reference project:** ~/Projects/ConAir — patterns for NSPanel floating window, ObservableObject state, AppDelegate bridging

**Design spec:** docs/superpowers/specs/2026-04-27-conductor-m0-design.md

---

## File Structure

```
Conductor/
├── Conductor.xcodeproj/
├── Conductor/
│   ├── ConductorApp.swift          # @main entry, NSPanel window setup
│   ├── AppDelegate.swift           # NSApplicationDelegate, app lifecycle
│   ├── ConductorState.swift        # Shared ObservableObject — workspaces, badges, panel state
│   ├── Workspace.swift             # Workspace model — name, title, AXUIElement ref, PID
│   ├── WindowDiscovery.swift       # AX enumeration, observers, roster management
│   ├── HookServer.swift            # NWListener HTTP server, /notify and /stop routes
│   ├── HookInstaller.swift         # Reads/writes ~/.claude/settings.json hook config
│   ├── PanelController.swift       # NSPanel subclass + hosting, collapse/expand logic
│   ├── PanelContentView.swift      # SwiftUI — collapsed pill and expanded roster views
│   ├── StatePersistence.swift      # Read/write ~/Library/Application Support/Conductor/state.json
│   ├── Assets.xcassets/
│   ├── Conductor.entitlements
│   └── Info.plist
└── ConductorTests/
    ├── WorkspaceTests.swift        # Title parsing, CWD matching
    ├── HookServerTests.swift       # HTTP payload parsing, badge state
    ├── HookInstallerTests.swift    # Settings.json read/write/backup
    └── StatePersistenceTests.swift # JSON round-trip
```

---

## Task 1: Xcode Project Scaffold

**Files:**
- Create: `Conductor/Conductor.xcodeproj/` (via xcodebuild)
- Create: `Conductor/Conductor/ConductorApp.swift`
- Create: `Conductor/Conductor/AppDelegate.swift`
- Create: `Conductor/Conductor/Info.plist`
- Create: `Conductor/Conductor/Conductor.entitlements`
- Create: `Conductor/Conductor/Assets.xcassets/`

- [ ] **Step 1: Create the Xcode project directory structure**

```bash
cd /Users/cdolan/Projects/vscode-squad
mkdir -p Conductor/Conductor
mkdir -p Conductor/ConductorTests
```

- [ ] **Step 2: Create Info.plist**

Create `Conductor/Conductor/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Conductor</string>
    <key>CFBundleDisplayName</key>
    <string>Conductor</string>
    <key>CFBundleIdentifier</key>
    <string>com.cdolan.conductor</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>Conductor</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAccessibilityUsageDescription</key>
    <string>Conductor needs Accessibility access to discover VS Code windows and bring them to focus when Claude Code needs your attention.</string>
</dict>
</plist>
```

Notes:
- `LSUIElement = true` makes this an agent app (no Dock icon). The floating panel is the only UI.
- `NSAccessibilityUsageDescription` is required for AX permission prompts.
- `LSMinimumSystemVersion` of 14.0 targets macOS Sonoma+.

- [ ] **Step 3: Create entitlements file**

Create `Conductor/Conductor/Conductor.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
</dict>
</plist>
```

Note: Sandbox is off. AX APIs and localhost HTTP server both require it. This is a developer tool, not an App Store app.

- [ ] **Step 4: Create Assets.xcassets with AccentColor**

```bash
mkdir -p Conductor/Conductor/Assets.xcassets/AccentColor.colorset
```

Create `Conductor/Conductor/Assets.xcassets/Contents.json`:

```json
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

Create `Conductor/Conductor/Assets.xcassets/AccentColor.colorset/Contents.json`:

```json
{
  "colors" : [
    {
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

- [ ] **Step 5: Create AppDelegate.swift**

Create `Conductor/Conductor/AppDelegate.swift`:

```swift
import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
```

Note: `.accessory` activation policy matches `LSUIElement = true` — no Dock icon, no main menu bar.

- [ ] **Step 6: Create ConductorApp.swift**

Create `Conductor/Conductor/ConductorApp.swift`:

```swift
import SwiftUI

@main
struct ConductorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
```

Note: We use a `Settings` scene as a placeholder. The actual UI is the NSPanel created in Task 5. SwiftUI's `Window` scene type doesn't support NSPanel's collection behaviors (`canJoinAllSpaces`, `stationary`), so we manage the panel window ourselves.

- [ ] **Step 7: Create the Xcode project file via swift package + xcodeproj generation**

Since we need an Xcode project (not SPM), create a `Package.swift` temporarily to bootstrap, then generate the xcodeproj:

Actually — the cleanest approach for a from-scratch Xcode project is to create it with `xcodebuild` or generate the pbxproj. But the simplest reliable method is to use a `Package.swift` with Xcode project generation.

Create `Conductor/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Conductor",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Conductor",
            path: "Conductor",
            resources: [.process("Assets.xcassets")]
        ),
        .testTarget(
            name: "ConductorTests",
            dependencies: ["Conductor"],
            path: "ConductorTests"
        ),
    ]
)
```

```bash
cd /Users/cdolan/Projects/vscode-squad/Conductor
swift package generate-xcodeproj
```

If `generate-xcodeproj` is unavailable on your toolchain, open the `Package.swift` directly in Xcode — it creates the project implicitly. Either way, the source files and build settings are defined by the Package.swift.

- [ ] **Step 8: Verify the project builds**

```bash
cd /Users/cdolan/Projects/vscode-squad/Conductor
swift build 2>&1
```

Expected: Build succeeds with no errors (the app does nothing yet, just launches an empty Settings scene).

- [ ] **Step 9: Commit**

```bash
cd /Users/cdolan/Projects/vscode-squad
git add Conductor/
git commit -m "feat: scaffold Conductor Xcode project with app entry point"
```

---

## Task 2: Workspace Model and Title Parsing

**Files:**
- Create: `Conductor/Conductor/Workspace.swift`
- Create: `Conductor/ConductorTests/WorkspaceTests.swift`

- [ ] **Step 1: Write failing tests for title parsing and CWD matching**

Create `Conductor/ConductorTests/WorkspaceTests.swift`:

```swift
import Testing
@testable import Conductor

@Suite("Workspace title parsing")
struct WorkspaceTitleParsingTests {
    @Test("Extracts workspace from 'file — project' format")
    func fileAndProject() {
        let name = Workspace.parseWorkspaceName(
            from: "main.swift — Conductor — Visual Studio Code"
        )
        #expect(name == "Conductor")
    }

    @Test("Extracts workspace from 'project — Visual Studio Code' format")
    func projectOnly() {
        let name = Workspace.parseWorkspaceName(
            from: "Conductor — Visual Studio Code"
        )
        #expect(name == "Conductor")
    }

    @Test("Strips Cursor suffix")
    func cursorSuffix() {
        let name = Workspace.parseWorkspaceName(
            from: "main.swift — MyProject — Cursor"
        )
        #expect(name == "MyProject")
    }

    @Test("Strips Code - Insiders suffix")
    func insidersSuffix() {
        let name = Workspace.parseWorkspaceName(
            from: "index.ts — webapp — Code - Insiders"
        )
        #expect(name == "webapp")
    }

    @Test("Returns full title when no separator found")
    func noSeparator() {
        let name = Workspace.parseWorkspaceName(from: "Welcome")
        #expect(name == "Welcome")
    }

    @Test("Handles em-dash and en-dash")
    func dashVariants() {
        let em = Workspace.parseWorkspaceName(from: "file.py — myproject — Visual Studio Code")
        let en = Workspace.parseWorkspaceName(from: "file.py – myproject – Visual Studio Code")
        #expect(em == "myproject")
        #expect(en == "myproject")
    }
}

@Suite("Workspace CWD matching")
struct WorkspaceCWDMatchingTests {
    @Test("Matches by basename")
    func basenameMatch() {
        let ws = Workspace(name: "vscode-squad", title: "test — vscode-squad", pid: 0, windowElement: nil)
        #expect(ws.matchesCWD("/Users/cdolan/Projects/vscode-squad"))
    }

    @Test("Does not match unrelated path")
    func noMatch() {
        let ws = Workspace(name: "vscode-squad", title: "test — vscode-squad", pid: 0, windowElement: nil)
        #expect(!ws.matchesCWD("/Users/cdolan/Projects/other-project"))
    }

    @Test("Matches when workspace name appears in path")
    func substringMatch() {
        let ws = Workspace(name: "feature", title: "test — feature", pid: 0, windowElement: nil)
        #expect(ws.matchesCWD("/Users/cdolan/Projects/repo-a/feature"))
    }

    @Test("Handles trailing slash in cwd")
    func trailingSlash() {
        let ws = Workspace(name: "vscode-squad", title: "test", pid: 0, windowElement: nil)
        #expect(ws.matchesCWD("/Users/cdolan/Projects/vscode-squad/"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/cdolan/Projects/vscode-squad/Conductor
swift test 2>&1
```

Expected: Compilation errors — `Workspace` type doesn't exist yet.

- [ ] **Step 3: Implement Workspace model**

Create `Conductor/Conductor/Workspace.swift`:

```swift
import ApplicationServices

struct Workspace: Identifiable {
    let id: String
    let name: String
    let title: String
    let pid: pid_t
    let windowElement: AXUIElement?

    init(name: String, title: String, pid: pid_t, windowElement: AXUIElement?) {
        self.id = "\(pid)-\(name)"
        self.name = name
        self.title = title
        self.pid = pid
        self.windowElement = windowElement
    }

    static func parseWorkspaceName(from title: String) -> String {
        var cleaned = title

        let suffixes = [
            " — Visual Studio Code",
            " – Visual Studio Code",
            " — Code - Insiders",
            " – Code - Insiders",
            " — Cursor",
            " – Cursor",
        ]
        for suffix in suffixes {
            if cleaned.hasSuffix(suffix) {
                cleaned = String(cleaned.dropLast(suffix.count))
                break
            }
        }

        for separator in [" — ", " – "] {
            if let range = cleaned.range(of: separator, options: .backwards) {
                return String(cleaned[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
        }

        return cleaned.trimmingCharacters(in: .whitespaces)
    }

    func matchesCWD(_ cwd: String) -> Bool {
        let normalizedCWD = cwd.hasSuffix("/") ? String(cwd.dropLast()) : cwd
        let basename = normalizedCWD.split(separator: "/").last.map(String.init) ?? normalizedCWD

        if name == basename {
            return true
        }

        if normalizedCWD.contains(name) {
            return true
        }

        return false
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd /Users/cdolan/Projects/vscode-squad/Conductor
swift test 2>&1
```

Expected: All 8 tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/cdolan/Projects/vscode-squad
git add Conductor/Conductor/Workspace.swift Conductor/ConductorTests/WorkspaceTests.swift
git commit -m "feat: add Workspace model with title parsing and CWD matching"
```

---

## Task 3: ConductorState — Shared Observable State

**Files:**
- Create: `Conductor/Conductor/ConductorState.swift`

- [ ] **Step 1: Create ConductorState**

Create `Conductor/Conductor/ConductorState.swift`:

```swift
import Foundation
import Combine

@MainActor
final class ConductorState: ObservableObject {
    static let shared = ConductorState()

    @Published var workspaces: [Workspace] = []
    @Published var badges: [String: Bool] = [:]
    @Published var lastBadgedWorkspace: String?
    @Published var panelExpanded: Bool = false
    @Published var mouseInside: Bool = false

    var badgeCount: Int {
        badges.values.filter { $0 }.count
    }

    var hasBadges: Bool {
        badgeCount > 0
    }

    func setBadge(for workspaceName: String) {
        badges[workspaceName] = true
        lastBadgedWorkspace = workspaceName
        panelExpanded = true
    }

    func clearBadge(for workspaceName: String) {
        badges[workspaceName] = nil
        if !hasBadges && !mouseInside {
            scheduleCollapse()
        }
    }

    func clearBadgeAndCollapse(for workspaceName: String) {
        badges[workspaceName] = nil
        if !hasBadges && !mouseInside {
            scheduleCollapse()
        }
    }

    func mouseEntered() {
        mouseInside = true
        expandCollapseTask?.cancel()
        panelExpanded = true
    }

    func mouseExited() {
        mouseInside = false
        if !hasBadges {
            scheduleCollapse()
        }
    }

    private var expandCollapseTask: Task<Void, Never>?

    private func scheduleCollapse() {
        expandCollapseTask?.cancel()
        expandCollapseTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            panelExpanded = false
        }
    }
}
```

- [ ] **Step 2: Verify build**

```bash
cd /Users/cdolan/Projects/vscode-squad/Conductor
swift build 2>&1
```

Expected: Compiles cleanly.

- [ ] **Step 3: Commit**

```bash
cd /Users/cdolan/Projects/vscode-squad
git add Conductor/Conductor/ConductorState.swift
git commit -m "feat: add ConductorState shared observable with badge and collapse logic"
```

---

## Task 4: HookServer — HTTP Listener for Claude Code Events

**Files:**
- Create: `Conductor/Conductor/HookServer.swift`
- Create: `Conductor/ConductorTests/HookServerTests.swift`

- [ ] **Step 1: Write failing tests for payload parsing**

Create `Conductor/ConductorTests/HookServerTests.swift`:

```swift
import Testing
import Foundation
@testable import Conductor

@Suite("HookPayload parsing")
struct HookPayloadTests {
    @Test("Parses valid notify payload")
    func validNotify() throws {
        let json = """
        {
            "session_id": "abc123",
            "cwd": "/Users/cdolan/Projects/vscode-squad",
            "hook_event_name": "Notification",
            "notification_type": "permission_prompt"
        }
        """.data(using: .utf8)!

        let payload = try JSONDecoder().decode(HookPayload.self, from: json)
        #expect(payload.sessionId == "abc123")
        #expect(payload.cwd == "/Users/cdolan/Projects/vscode-squad")
        #expect(payload.hookEventName == "Notification")
    }

    @Test("Parses valid stop payload")
    func validStop() throws {
        let json = """
        {
            "session_id": "abc123",
            "cwd": "/Users/cdolan/Projects/vscode-squad",
            "hook_event_name": "Stop"
        }
        """.data(using: .utf8)!

        let payload = try JSONDecoder().decode(HookPayload.self, from: json)
        #expect(payload.hookEventName == "Stop")
    }

    @Test("Ignores unknown fields without failing")
    func unknownFields() throws {
        let json = """
        {
            "session_id": "abc123",
            "cwd": "/some/path",
            "hook_event_name": "Notification",
            "transcript_path": "/some/transcript.jsonl",
            "permission_mode": "default",
            "future_field": "should be ignored"
        }
        """.data(using: .utf8)!

        let payload = try JSONDecoder().decode(HookPayload.self, from: json)
        #expect(payload.cwd == "/some/path")
    }

    @Test("Fails on missing cwd")
    func missingCwd() {
        let json = """
        {
            "session_id": "abc123",
            "hook_event_name": "Notification"
        }
        """.data(using: .utf8)!

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(HookPayload.self, from: json)
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/cdolan/Projects/vscode-squad/Conductor
swift test 2>&1
```

Expected: Compilation error — `HookPayload` doesn't exist.

- [ ] **Step 3: Implement HookServer**

Create `Conductor/Conductor/HookServer.swift`:

```swift
import Foundation
import Network
import OSLog

struct HookPayload: Decodable {
    let sessionId: String
    let cwd: String
    let hookEventName: String

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case cwd
        case hookEventName = "hook_event_name"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sessionId = try container.decode(String.self, forKey: .sessionId)
        self.cwd = try container.decode(String.self, forKey: .cwd)
        self.hookEventName = try container.decode(String.self, forKey: .hookEventName)
    }
}

@MainActor
final class HookServer {
    private let port: UInt16
    private var listener: NWListener?
    private let state: ConductorState
    private let logger = Logger(subsystem: "com.cdolan.conductor", category: "HookServer")

    init(port: UInt16 = 9876, state: ConductorState) {
        self.port = port
        self.state = state
    }

    func start() {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        } catch {
            logger.error("Failed to create listener: \(error)")
            return
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener?.stateUpdateHandler = { [weak self] newState in
            switch newState {
            case .ready:
                self?.logger.info("Hook server listening on 127.0.0.1:\(self?.port ?? 0)")
            case .failed(let error):
                self?.logger.error("Hook server failed: \(error)")
            default:
                break
            }
        }

        listener?.start(queue: .main)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        receiveHTTPRequest(on: connection)
    }

    private func receiveHTTPRequest(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let error {
                self.logger.error("Connection receive error: \(error)")
                connection.cancel()
                return
            }

            guard let data else {
                connection.cancel()
                return
            }

            let (statusCode, responseBody) = self.processHTTPRequest(data)
            self.sendHTTPResponse(on: connection, statusCode: statusCode, body: responseBody)

            if isComplete {
                connection.cancel()
            }
        }
    }

    private nonisolated func processHTTPRequest(_ data: Data) -> (Int, String) {
        guard let raw = String(data: data, encoding: .utf8) else {
            return (400, "bad request")
        }

        let lines = raw.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let requestLine = lines.first else {
            return (400, "bad request")
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            return (400, "bad request")
        }

        let method = String(parts[0])
        let path = String(parts[1])

        guard method == "POST" else {
            return (405, "method not allowed")
        }

        guard path == "/notify" || path == "/stop" else {
            return (404, "not found")
        }

        guard let bodyStart = raw.range(of: "\r\n\r\n") else {
            return (400, "no body")
        }

        let bodyString = String(raw[bodyStart.upperBound...])
        guard let bodyData = bodyString.data(using: .utf8) else {
            return (400, "bad body encoding")
        }

        let payload: HookPayload
        do {
            payload = try JSONDecoder().decode(HookPayload.self, from: bodyData)
        } catch {
            return (400, "bad payload")
        }

        DispatchQueue.main.async { [payload, path] in
            self.routePayload(payload, path: path)
        }

        return (200, "ok")
    }

    @MainActor
    private func routePayload(_ payload: HookPayload, path: String) {
        guard let workspace = state.workspaces.first(where: { $0.matchesCWD(payload.cwd) }) else {
            logger.warning("No workspace match for cwd: \(payload.cwd)")
            return
        }

        switch path {
        case "/notify":
            logger.info("Badge set for \(workspace.name) (session: \(payload.sessionId))")
            state.setBadge(for: workspace.name)
        case "/stop":
            logger.info("Badge cleared for \(workspace.name) (session: \(payload.sessionId))")
            state.clearBadge(for: workspace.name)
        default:
            break
        }
    }

    private func sendHTTPResponse(on connection: NWConnection, statusCode: Int, body: String) {
        let statusText: String
        switch statusCode {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        case 405: statusText = "Method Not Allowed"
        default: statusText = "Error"
        }

        let response = "HTTP/1.1 \(statusCode) \(statusText)\r\nContent-Type: text/plain\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        let responseData = Data(response.utf8)

        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd /Users/cdolan/Projects/vscode-squad/Conductor
swift test 2>&1
```

Expected: All 4 payload parsing tests pass. (The server itself is tested via integration in Task 8.)

- [ ] **Step 5: Commit**

```bash
cd /Users/cdolan/Projects/vscode-squad
git add Conductor/Conductor/HookServer.swift Conductor/ConductorTests/HookServerTests.swift
git commit -m "feat: add HookServer with NWListener and Claude Code payload parsing"
```

---

## Task 5: PanelController — NSPanel Window Management

**Files:**
- Create: `Conductor/Conductor/PanelController.swift`

- [ ] **Step 1: Implement PanelController**

Create `Conductor/Conductor/PanelController.swift`:

```swift
import AppKit
import SwiftUI
import Combine

@MainActor
final class PanelController {
    private var panel: NSPanel?
    private let state: ConductorState
    private var cancellables = Set<AnyCancellable>()

    private let collapsedWidth: CGFloat = 36
    private let collapsedHeight: CGFloat = 80
    private let expandedWidth: CGFloat = 220
    private let edgeMargin: CGFloat = 0

    init(state: ConductorState) {
        self.state = state
    }

    func show() {
        guard panel == nil else { return }

        let contentView = PanelContentView(state: state)
        let hostingView = NSHostingView(rootView: contentView)

        let frame = collapsedFrame()
        let styleMask: NSWindow.StyleMask = [.nonactivatingPanel, .borderless]
        let panel = NSPanel(contentRect: frame, styleMask: styleMask, backing: .buffered, defer: false)

        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = true
        panel.contentView = hostingView

        panel.orderFrontRegardless()
        self.panel = panel

        observeState()
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        cancellables.removeAll()
    }

    private func observeState() {
        state.$panelExpanded
            .removeDuplicates()
            .sink { [weak self] expanded in
                self?.updatePanelSize(expanded: expanded)
            }
            .store(in: &cancellables)
    }

    private func updatePanelSize(expanded: Bool) {
        guard let panel else { return }

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let screenFrame = screen.visibleFrame

        if expanded {
            let height = max(
                collapsedHeight,
                CGFloat(state.workspaces.count) * 56 + 52
            )
            let clampedHeight = min(height, screenFrame.height - 40)
            let x = screenFrame.maxX - expandedWidth - edgeMargin
            let y = screenFrame.midY - (clampedHeight / 2)
            panel.setFrame(NSRect(x: x, y: y, width: expandedWidth, height: clampedHeight), display: true)
        } else {
            let x = screenFrame.maxX - collapsedWidth - edgeMargin
            let y = screenFrame.midY - (collapsedHeight / 2)
            panel.setFrame(NSRect(x: x, y: y, width: collapsedWidth, height: collapsedHeight), display: true)
        }
    }

    private func collapsedFrame() -> NSRect {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let screenFrame = screen.visibleFrame
        let x = screenFrame.maxX - collapsedWidth - edgeMargin
        let y = screenFrame.midY - (collapsedHeight / 2)
        return NSRect(x: x, y: y, width: collapsedWidth, height: collapsedHeight)
    }
}
```

- [ ] **Step 2: Verify build**

```bash
cd /Users/cdolan/Projects/vscode-squad/Conductor
swift build 2>&1
```

Expected: Compilation error for missing `PanelContentView` — that's Task 6. Create a stub:

Create a temporary stub at the top of `PanelController.swift` or as a separate file — we'll replace it in Task 6. Add this to the bottom of `PanelController.swift` temporarily:

Actually, skip the build check — Task 6 creates PanelContentView immediately next. Build after Task 6.

- [ ] **Step 3: Commit**

```bash
cd /Users/cdolan/Projects/vscode-squad
git add Conductor/Conductor/PanelController.swift
git commit -m "feat: add PanelController with NSPanel setup and collapse/expand sizing"
```

---

## Task 6: PanelContentView — SwiftUI Collapsed Pill + Expanded Roster

**Files:**
- Create: `Conductor/Conductor/PanelContentView.swift`

- [ ] **Step 1: Implement PanelContentView**

Create `Conductor/Conductor/PanelContentView.swift`:

```swift
import SwiftUI
import ApplicationServices

struct PanelContentView: View {
    @ObservedObject var state: ConductorState

    var body: some View {
        Group {
            if state.panelExpanded {
                expandedView
            } else {
                collapsedView
            }
        }
        .onHover { hovering in
            if hovering {
                hoverTask?.cancel()
                hoverTask = Task {
                    try? await Task.sleep(for: .milliseconds(200))
                    guard !Task.isCancelled else { return }
                    state.mouseEntered()
                }
            } else {
                hoverTask?.cancel()
                state.mouseExited()
            }
        }
    }

    @State private var hoverTask: Task<Void, Never>?

    private var collapsedView: some View {
        VStack {
            if state.hasBadges {
                Text("\(state.badgeCount)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            } else {
                Circle()
                    .fill(.white.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.black.opacity(state.hasBadges ? 0.85 : 0.5))
        )
    }

    private var expandedView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Conductor")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(state.workspaces) { workspace in
                        WorkspaceRow(
                            workspace: workspace,
                            isBadged: state.badges[workspace.name] == true,
                            onTap: { focusWorkspace(workspace) }
                        )
                    }
                }
                .padding(.horizontal, 8)
            }

            if state.workspaces.isEmpty {
                Text("No VS Code windows")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.black.opacity(0.85))
        )
    }

    private func focusWorkspace(_ workspace: Workspace) {
        if let element = workspace.windowElement {
            AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        }

        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == workspace.pid }) {
            app.activate()
        }

        state.clearBadgeAndCollapse(for: workspace.name)
    }
}

struct WorkspaceRow: View {
    let workspace: Workspace
    let isBadged: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(workspace.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(workspace.title)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }

            Spacer()

            if isBadged {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 10, height: 10)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(badgeBackground)
        )
        .onHover { isHovered = $0 }
        .onTapGesture { onTap() }
    }

    private var badgeBackground: Color {
        if isBadged {
            return .orange.opacity(0.2)
        } else if isHovered {
            return .white.opacity(0.08)
        } else {
            return .white.opacity(0.04)
        }
    }
}
```

- [ ] **Step 2: Verify build**

```bash
cd /Users/cdolan/Projects/vscode-squad/Conductor
swift build 2>&1
```

Expected: Build succeeds (PanelController + PanelContentView both compile).

- [ ] **Step 3: Commit**

```bash
cd /Users/cdolan/Projects/vscode-squad
git add Conductor/Conductor/PanelContentView.swift
git commit -m "feat: add SwiftUI panel views — collapsed pill and expanded roster"
```

---

## Task 7: WindowDiscovery — AX-Based VS Code Window Enumeration

**Files:**
- Create: `Conductor/Conductor/WindowDiscovery.swift`

- [ ] **Step 1: Implement WindowDiscovery**

Create `Conductor/Conductor/WindowDiscovery.swift`:

```swift
import AppKit
import ApplicationServices
import OSLog

@MainActor
final class WindowDiscovery {
    private let state: ConductorState
    private let logger = Logger(subsystem: "com.cdolan.conductor", category: "WindowDiscovery")
    private var observers: [pid_t: AXObserver] = [:]
    private var refreshTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []

    private let bundleIDs: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92",
    ]

    init(state: ConductorState) {
        self.state = state
    }

    func start() {
        refresh()
        startSafetyNetTimer()
        observeAppLifecycle()
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()
        removeAllAXObservers()
    }

    func refresh() {
        var newWorkspaces: [Workspace] = []

        let apps = NSWorkspace.shared.runningApplications.filter {
            guard let bundleID = $0.bundleIdentifier else { return false }
            return bundleIDs.contains(bundleID)
        }

        for app in apps {
            let pid = app.processIdentifier
            let axApp = AXUIElementCreateApplication(pid)

            var windowsRef: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)
            guard result == .success, let windows = windowsRef as? [AXUIElement] else {
                continue
            }

            for window in windows {
                guard let title = axTitle(of: window), !title.isEmpty else { continue }
                guard isStandardWindow(window) else { continue }

                let name = Workspace.parseWorkspaceName(from: title)
                let workspace = Workspace(name: name, title: title, pid: pid, windowElement: window)
                newWorkspaces.append(workspace)
            }

            setupAXObserver(for: pid, appElement: axApp)
        }

        newWorkspaces.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        state.workspaces = newWorkspaces
        logger.info("Refreshed: \(newWorkspaces.count) workspace(s)")
    }

    private func axTitle(of element: AXUIElement) -> String? {
        var titleRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
        guard result == .success else { return nil }
        return titleRef as? String
    }

    private func isStandardWindow(_ window: AXUIElement) -> Bool {
        var roleRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &roleRef)
        guard result == .success, let role = roleRef as? String else { return false }
        return role == kAXWindowRole as String
    }

    private func setupAXObserver(for pid: pid_t, appElement: AXUIElement) {
        guard observers[pid] == nil else { return }

        var observer: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let discovery = Unmanaged<WindowDiscovery>.fromOpaque(refcon).takeUnretainedValue()
            DispatchQueue.main.async {
                discovery.refresh()
            }
        }

        let result = AXObserverCreate(pid, callback, &observer)
        guard result == .success, let observer else { return }

        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        AXObserverAddNotification(observer, appElement, kAXWindowCreatedNotification as CFString, refcon)
        AXObserverAddNotification(observer, appElement, kAXUIElementDestroyedNotification as CFString, refcon)

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        observers[pid] = observer
        logger.info("AX observer registered for PID \(pid)")
    }

    private func removeAllAXObservers() {
        for (_, observer) in observers {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observers.removeAll()
    }

    private func startSafetyNetTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    private func observeAppLifecycle() {
        let center = NSWorkspace.shared.notificationCenter

        let launchObserver = center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier,
                  self?.bundleIDs.contains(bundleID) == true else { return }
            Task { @MainActor in
                self?.refresh()
            }
        }

        let terminateObserver = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            Task { @MainActor in
                self?.observers.removeValue(forKey: pid)
                self?.refresh()
            }
        }

        workspaceObservers = [launchObserver, terminateObserver]
    }
}
```

- [ ] **Step 2: Verify build**

```bash
cd /Users/cdolan/Projects/vscode-squad/Conductor
swift build 2>&1
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
cd /Users/cdolan/Projects/vscode-squad
git add Conductor/Conductor/WindowDiscovery.swift
git commit -m "feat: add WindowDiscovery with AX enumeration and observer-based updates"
```

---

## Task 8: HookInstaller — Settings.json Management

**Files:**
- Create: `Conductor/Conductor/HookInstaller.swift`
- Create: `Conductor/ConductorTests/HookInstallerTests.swift`

- [ ] **Step 1: Write failing tests for hook installer**

Create `Conductor/ConductorTests/HookInstallerTests.swift`:

```swift
import Testing
import Foundation
@testable import Conductor

@Suite("HookInstaller")
struct HookInstallerTests {

    @Test("Detects hooks are missing in empty settings")
    func missingInEmpty() throws {
        let json: [String: Any] = [:]
        let data = try JSONSerialization.data(withJSONObject: json)
        #expect(!HookInstaller.hooksPresent(in: data))
    }

    @Test("Detects hooks are present")
    func hooksPresent() throws {
        let settings: [String: Any] = [
            "hooks": [
                "Notification": [
                    ["hooks": [["type": "http", "url": "http://127.0.0.1:9876/notify"]]]
                ],
                "Stop": [
                    ["hooks": [["type": "http", "url": "http://127.0.0.1:9876/stop"]]]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: settings)
        #expect(HookInstaller.hooksPresent(in: data))
    }

    @Test("Merges hooks into existing settings without clobbering")
    func mergesWithoutClobbering() throws {
        let existing: [String: Any] = [
            "permissions": ["allow": ["Read"]],
            "hooks": [
                "PreToolUse": [
                    ["hooks": [["type": "command", "command": "echo hello"]]]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: existing)
        let merged = try HookInstaller.mergeHooks(into: data)
        let result = try JSONSerialization.jsonObject(with: merged) as! [String: Any]

        let permissions = result["permissions"] as? [String: Any]
        #expect(permissions != nil)

        let hooks = result["hooks"] as! [String: Any]
        #expect(hooks["PreToolUse"] != nil)
        #expect(hooks["Notification"] != nil)
        #expect(hooks["Stop"] != nil)
    }

    @Test("Creates settings from scratch when file is empty")
    func createsFromScratch() throws {
        let merged = try HookInstaller.mergeHooks(into: Data("{}".utf8))
        let result = try JSONSerialization.jsonObject(with: merged) as! [String: Any]
        let hooks = result["hooks"] as! [String: Any]
        #expect(hooks["Notification"] != nil)
        #expect(hooks["Stop"] != nil)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/cdolan/Projects/vscode-squad/Conductor
swift test 2>&1
```

Expected: Compilation error — `HookInstaller` doesn't exist.

- [ ] **Step 3: Implement HookInstaller**

Create `Conductor/Conductor/HookInstaller.swift`:

```swift
import Foundation
import OSLog

enum HookInstaller {
    private static let logger = Logger(subsystem: "com.cdolan.conductor", category: "HookInstaller")

    static let conductorNotifyURL = "http://127.0.0.1:9876/notify"
    static let conductorStopURL = "http://127.0.0.1:9876/stop"

    static var settingsPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.claude/settings.json"
    }

    static func hooksPresent(in data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return false
        }

        let hasNotify = hookArrayContainsURL(hooks["Notification"], url: conductorNotifyURL)
        let hasStop = hookArrayContainsURL(hooks["Stop"], url: conductorStopURL)
        return hasNotify && hasStop
    }

    static func checkInstalled() -> Bool {
        guard let data = FileManager.default.contents(atPath: settingsPath) else {
            return false
        }
        return hooksPresent(in: data)
    }

    static func install() throws {
        let fileManager = FileManager.default
        let settingsURL = URL(fileURLWithPath: settingsPath)

        let existingData: Data
        if fileManager.fileExists(atPath: settingsPath) {
            existingData = try Data(contentsOf: settingsURL)
            let backupPath = settingsPath + ".backup.\(Int(Date().timeIntervalSince1970))"
            try fileManager.copyItem(atPath: settingsPath, toPath: backupPath)
            logger.info("Backed up settings to \(backupPath)")
        } else {
            existingData = Data("{}".utf8)
            let dir = settingsURL.deletingLastPathComponent().path
            try fileManager.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        let merged = try mergeHooks(into: existingData)
        try merged.write(to: settingsURL)
        logger.info("Hooks installed to \(settingsPath)")
    }

    static func mergeHooks(into existingData: Data) throws -> Data {
        var json = (try? JSONSerialization.jsonObject(with: existingData) as? [String: Any]) ?? [:]
        var hooks = (json["hooks"] as? [String: Any]) ?? [:]

        let notifyHook: [String: Any] = ["type": "http", "url": conductorNotifyURL]
        let stopHook: [String: Any] = ["type": "http", "url": conductorStopURL]

        if !hookArrayContainsURL(hooks["Notification"], url: conductorNotifyURL) {
            var existing = (hooks["Notification"] as? [[String: Any]]) ?? []
            existing.append(["hooks": [notifyHook]])
            hooks["Notification"] = existing
        }

        if !hookArrayContainsURL(hooks["Stop"], url: conductorStopURL) {
            var existing = (hooks["Stop"] as? [[String: Any]]) ?? []
            existing.append(["hooks": [stopHook]])
            hooks["Stop"] = existing
        }

        json["hooks"] = hooks
        return try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
    }

    private static func hookArrayContainsURL(_ value: Any?, url: String) -> Bool {
        guard let entries = value as? [[String: Any]] else { return false }
        for entry in entries {
            guard let hooks = entry["hooks"] as? [[String: Any]] else { continue }
            for hook in hooks {
                if hook["type"] as? String == "http", hook["url"] as? String == url {
                    return true
                }
            }
        }
        return false
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd /Users/cdolan/Projects/vscode-squad/Conductor
swift test 2>&1
```

Expected: All 4 HookInstaller tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/cdolan/Projects/vscode-squad
git add Conductor/Conductor/HookInstaller.swift Conductor/ConductorTests/HookInstallerTests.swift
git commit -m "feat: add HookInstaller for ~/.claude/settings.json management with backup"
```

---

## Task 9: StatePersistence — Panel Position and Settings

**Files:**
- Create: `Conductor/Conductor/StatePersistence.swift`
- Create: `Conductor/ConductorTests/StatePersistenceTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Conductor/ConductorTests/StatePersistenceTests.swift`:

```swift
import Testing
import Foundation
@testable import Conductor

@Suite("StatePersistence")
struct StatePersistenceTests {
    @Test("Round-trips persisted state")
    func roundTrip() throws {
        let original = PersistedState(panelX: 100.5, panelY: 200.0, hooksInstalled: true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PersistedState.self, from: data)
        #expect(decoded.panelX == 100.5)
        #expect(decoded.panelY == 200.0)
        #expect(decoded.hooksInstalled == true)
    }

    @Test("Provides defaults when file missing")
    func defaultsOnMissing() {
        let state = StatePersistence.load(from: "/tmp/nonexistent-conductor-state.json")
        #expect(state.panelX == nil)
        #expect(state.panelY == nil)
        #expect(state.hooksInstalled == false)
    }

    @Test("Writes and reads back from disk")
    func writeAndRead() throws {
        let path = "/tmp/conductor-test-state-\(UUID().uuidString).json"
        let original = PersistedState(panelX: 50, panelY: 300, hooksInstalled: true)
        try StatePersistence.save(original, to: path)
        let loaded = StatePersistence.load(from: path)
        #expect(loaded.panelX == 50)
        #expect(loaded.panelY == 300)
        #expect(loaded.hooksInstalled == true)
        try? FileManager.default.removeItem(atPath: path)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/cdolan/Projects/vscode-squad/Conductor
swift test 2>&1
```

Expected: Compilation error — types don't exist.

- [ ] **Step 3: Implement StatePersistence**

Create `Conductor/Conductor/StatePersistence.swift`:

```swift
import Foundation
import OSLog

struct PersistedState: Codable {
    var panelX: Double?
    var panelY: Double?
    var hooksInstalled: Bool

    init(panelX: Double? = nil, panelY: Double? = nil, hooksInstalled: Bool = false) {
        self.panelX = panelX
        self.panelY = panelY
        self.hooksInstalled = hooksInstalled
    }
}

enum StatePersistence {
    private static let logger = Logger(subsystem: "com.cdolan.conductor", category: "StatePersistence")

    static var defaultPath: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Conductor/state.json").path
    }

    static func load(from path: String? = nil) -> PersistedState {
        let filePath = path ?? defaultPath
        guard let data = FileManager.default.contents(atPath: filePath) else {
            return PersistedState()
        }
        do {
            return try JSONDecoder().decode(PersistedState.self, from: data)
        } catch {
            logger.error("Failed to decode state: \(error)")
            return PersistedState()
        }
    }

    static func save(_ state: PersistedState, to path: String? = nil) throws {
        let filePath = path ?? defaultPath
        let url = URL(fileURLWithPath: filePath)
        let dir = url.deletingLastPathComponent().path

        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(state)
        try data.write(to: url)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd /Users/cdolan/Projects/vscode-squad/Conductor
swift test 2>&1
```

Expected: All 3 StatePersistence tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/cdolan/Projects/vscode-squad
git add Conductor/Conductor/StatePersistence.swift Conductor/ConductorTests/StatePersistenceTests.swift
git commit -m "feat: add StatePersistence for panel position and settings"
```

---

## Task 10: Wire Everything Together in App Lifecycle

**Files:**
- Modify: `Conductor/Conductor/AppDelegate.swift`
- Modify: `Conductor/Conductor/ConductorApp.swift`

- [ ] **Step 1: Update AppDelegate to orchestrate all components**

Replace `Conductor/Conductor/AppDelegate.swift` with:

```swift
import Cocoa
import OSLog

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.cdolan.conductor", category: "App")
    private var panelController: PanelController?
    private var hookServer: HookServer?
    private var windowDiscovery: WindowDiscovery?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if !AXIsProcessTrusted() {
            logger.warning("Accessibility permission not granted — requesting")
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }

        let state = ConductorState.shared

        if !HookInstaller.checkInstalled() {
            logger.info("Hooks not installed — installing")
            do {
                try HookInstaller.install()
                logger.info("Hooks installed successfully")
            } catch {
                logger.error("Failed to install hooks: \(error)")
            }
        }

        windowDiscovery = WindowDiscovery(state: state)
        windowDiscovery?.start()

        hookServer = HookServer(state: state)
        hookServer?.start()

        panelController = PanelController(state: state)
        panelController?.show()

        logger.info("Conductor M0 running")
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowDiscovery?.stop()
        hookServer?.stop()
        panelController?.hide()
    }
}
```

- [ ] **Step 2: Verify ConductorApp.swift is unchanged**

`Conductor/Conductor/ConductorApp.swift` should still be:

```swift
import SwiftUI

@main
struct ConductorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
```

No changes needed — the AppDelegate handles all orchestration.

- [ ] **Step 3: Build the complete app**

```bash
cd /Users/cdolan/Projects/vscode-squad/Conductor
swift build 2>&1
```

Expected: Build succeeds with no errors.

- [ ] **Step 4: Run all tests**

```bash
cd /Users/cdolan/Projects/vscode-squad/Conductor
swift test 2>&1
```

Expected: All tests pass (WorkspaceTests: 8, HookServerTests: 4, HookInstallerTests: 4, StatePersistenceTests: 3 — 19 total).

- [ ] **Step 5: Commit**

```bash
cd /Users/cdolan/Projects/vscode-squad
git add Conductor/Conductor/AppDelegate.swift
git commit -m "feat: wire up app lifecycle — WindowDiscovery, HookServer, PanelController"
```

---

## Task 11: Manual Integration Test

**Files:** None — this is a verification task.

- [ ] **Step 1: Launch the app**

```bash
cd /Users/cdolan/Projects/vscode-squad/Conductor
swift run 2>&1 &
```

Expected: The app launches. macOS prompts for Accessibility permission (grant it in System Settings → Privacy & Security → Accessibility). A small dark pill appears on the right edge of your main display.

- [ ] **Step 2: Open 2+ VS Code windows with different projects**

Open at least two VS Code windows pointing to different project folders. The pill should remain collapsed.

Hover over the pill — after ~200ms it should expand to show the roster with one row per VS Code window.

- [ ] **Step 3: Test the hook server**

Send a test notify event:

```bash
curl -X POST http://127.0.0.1:9876/notify \
  -H "Content-Type: application/json" \
  -d '{"session_id":"test-123","cwd":"/Users/cdolan/Projects/vscode-squad","hook_event_name":"Notification"}'
```

Expected: The pill auto-expands and shows a badge count. The matching workspace row has an orange badge dot.

- [ ] **Step 4: Test click-to-focus**

Click the badged workspace row. Expected: the corresponding VS Code window comes to the front. The badge clears. If no other badges remain and your mouse leaves the panel, it collapses back to the pill after ~300ms.

- [ ] **Step 5: Test stop event clears badge**

Set a badge first, then clear it:

```bash
curl -X POST http://127.0.0.1:9876/notify \
  -H "Content-Type: application/json" \
  -d '{"session_id":"test-456","cwd":"/Users/cdolan/Projects/vscode-squad","hook_event_name":"Notification"}'

curl -X POST http://127.0.0.1:9876/stop \
  -H "Content-Type: application/json" \
  -d '{"session_id":"test-456","cwd":"/Users/cdolan/Projects/vscode-squad","hook_event_name":"Stop"}'
```

Expected: Badge appears on first curl, clears on second curl.

- [ ] **Step 6: Verify hooks were installed**

```bash
cat ~/.claude/settings.json | python3 -m json.tool
```

Expected: The `hooks` section contains `Notification` and `Stop` entries pointing to `http://127.0.0.1:9876/notify` and `http://127.0.0.1:9876/stop`. Existing settings are preserved.

- [ ] **Step 7: Commit any fixes discovered during testing**

If any bugs were found and fixed during integration testing:

```bash
cd /Users/cdolan/Projects/vscode-squad
git add -A
git commit -m "fix: address issues found during integration testing"
```
