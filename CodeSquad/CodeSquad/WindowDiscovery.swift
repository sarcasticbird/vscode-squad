import AppKit
import ApplicationServices
import OSLog

@MainActor
final class WindowDiscovery {
    private let state: CodeSquadState
    private let logger = Logger(subsystem: "com.cdolan.codesquad", category: "WindowDiscovery")
    private var observers: [pid_t: AXObserver] = [:]
    private var refreshTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []

    private let bundleIDs: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92",
    ]

    init(state: CodeSquadState) {
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
        state.axTrusted = AXIsProcessTrusted()
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
        applyExtensionFolders(&newWorkspaces)
        resolveWorkspaceFolders(&newWorkspaces)
        state.workspaces = newWorkspaces
        if !newWorkspaces.isEmpty {
            state.axTrusted = true
        }
        state.initialScanDone = true
        clearAttentionForFocusedWindow(apps: apps)
        logger.debug("Refreshed: \(newWorkspaces.count) workspace(s)")
    }

    private nonisolated func axTitle(of element: AXUIElement) -> String? {
        var titleRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
        guard result == .success else { return nil }
        return titleRef as? String
    }

    private func clearAttentionForFocusedWindow(apps: [NSRunningApplication]) {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let bundleID = frontApp.bundleIdentifier,
              bundleIDs.contains(bundleID) else { return }

        let axApp = AXUIElementCreateApplication(frontApp.processIdentifier)
        var focusedRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedRef)
        guard result == .success, let title = axTitle(of: focusedRef as! AXUIElement) else { return }

        let name = Workspace.parseWorkspaceName(from: title)
        state.clearAttention(for: name)
    }

    private nonisolated func isStandardWindow(_ window: AXUIElement) -> Bool {
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
        logger.debug("AX observer registered for PID \(pid)")
    }

    private func removeAllAXObservers() {
        for (_, observer) in observers {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observers.removeAll()
    }

    private func applyExtensionFolders(_ workspaces: inout [Workspace]) {
        for i in workspaces.indices {
            if let folders = state.extensionFolders[workspaces[i].name], !folders.isEmpty {
                workspaces[i].folderPaths = folders
            }
        }
    }

    private nonisolated func resolveWorkspaceFolders(_ workspaces: inout [Workspace]) {
        let folderMap = loadWorkspaceFolderMap()
        for i in workspaces.indices {
            guard workspaces[i].folderPaths.isEmpty else { continue }
            if let folders = folderMap[workspaces[i].name] {
                workspaces[i].folderPaths = folders
            }
        }
    }

    private nonisolated func loadWorkspaceFolderMap() -> [String: [String]] {
        var result: [String: [String]] = [:]
        let fm = FileManager.default

        let supportDirs = [
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Code/User/workspaceStorage"),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Code - Insiders/User/workspaceStorage"),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Cursor/User/workspaceStorage"),
        ]

        for storageDir in supportDirs {
            guard let entries = try? fm.contentsOfDirectory(atPath: storageDir.path) else { continue }
            for entry in entries {
                let wsJsonPath = storageDir.appendingPathComponent(entry).appendingPathComponent("workspace.json").path
                guard let data = fm.contents(atPath: wsJsonPath),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let wsURI = json["workspace"] as? String,
                      wsURI.contains(".code-workspace") else { continue }

                guard let wsFileURL = URL(string: wsURI),
                      wsFileURL.isFileURL else { continue }

                let wsFilePath = wsFileURL.path
                let wsName = (wsFilePath as NSString).lastPathComponent
                    .replacingOccurrences(of: ".code-workspace", with: "")

                guard let wsData = fm.contents(atPath: wsFilePath),
                      let wsJson = try? JSONSerialization.jsonObject(with: wsData) as? [String: Any],
                      let folders = wsJson["folders"] as? [[String: Any]] else { continue }

                let wsDir = URL(fileURLWithPath: wsFilePath).deletingLastPathComponent()
                var resolved: [String] = []
                for folder in folders {
                    guard let relativePath = folder["path"] as? String else { continue }
                    let absURL = wsDir.appendingPathComponent(relativePath).standardized
                    resolved.append(absURL.path)
                }

                if !resolved.isEmpty {
                    result[wsName] = resolved
                }
            }
        }

        return result
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
