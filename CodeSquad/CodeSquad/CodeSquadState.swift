import Foundation
import Combine
import ApplicationServices

enum ClaudeStatus: Equatable {
    case inactive
    case idle
    case working
    case permissionNeeded
    case needsAttention
}

@MainActor
final class CodeSquadState: ObservableObject {
    static let shared = CodeSquadState()

    @Published var workspaces: [Workspace] = []
    @Published var claudeStatus: [String: ClaudeStatus] = [:]
    @Published var claudeSessions: [String: [ClaudeSession]] = [:]
    @Published var panelMinimized: Bool = false
    @Published var axTrusted: Bool = AXIsProcessTrusted()
    @Published var initialScanDone: Bool = false

    var extensionFolders: [String: [String]] = [:]

    var attentionCount: Int {
        claudeStatus.values.filter { $0 == .needsAttention || $0 == .permissionNeeded }.count
    }

    var hasAttention: Bool {
        attentionCount > 0
    }

    func claudeProcessFound(workspace: String, sessions: [ClaudeSession]) {
        claudeSessions[workspace] = sessions
        let current = claudeStatus[workspace]
        if current == nil || current == .inactive {
            claudeStatus[workspace] = .idle
        }
    }

    func claudeProcessGone(workspace: String) {
        claudeSessions.removeValue(forKey: workspace)
        let current = claudeStatus[workspace]
        if current != .needsAttention && current != .permissionNeeded {
            claudeStatus[workspace] = .inactive
        }
    }

    func claudeWorking(workspace: String) {
        let current = claudeStatus[workspace]
        if current != .needsAttention {
            claudeStatus[workspace] = .working
        }
    }

    func claudePermissionNeeded(workspace: String) {
        claudeStatus[workspace] = .permissionNeeded
        panelMinimized = false
    }

    func claudeNeedsAttention(workspace: String) {
        if claudeStatus[workspace] == .permissionNeeded { return }
        claudeStatus[workspace] = .needsAttention
        panelMinimized = false
    }

    func claudeFinished(workspace: String) {
        let current = claudeStatus[workspace]
        if current == .working || current == .permissionNeeded {
            claudeStatus[workspace] = .needsAttention
            panelMinimized = false
        }
    }

    func clearStatusAndCollapse(for workspace: String) {
        let current = claudeStatus[workspace]
        if current == .needsAttention || current == .permissionNeeded {
            claudeStatus[workspace] = .idle
        }
    }

    func registerExtensionWorkspace(name: String, folderPaths: [String]) {
        extensionFolders[name] = folderPaths
        if let idx = workspaces.firstIndex(where: { $0.name == name }) {
            workspaces[idx].folderPaths = folderPaths
        }
    }

    func deregisterExtensionWorkspace(name: String) {
        extensionFolders.removeValue(forKey: name)
    }

    func toggleMinimized() {
        panelMinimized.toggle()
    }

    func refreshAXStatus() {
        axTrusted = AXIsProcessTrusted()
    }
}
