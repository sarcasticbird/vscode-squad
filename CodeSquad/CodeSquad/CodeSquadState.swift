import Foundation
import Combine
import SwiftUI

enum ClaudeStatus: Equatable {
    case inactive
    case idle
    case working
    case permissionNeeded
    case needsAttention
}

enum ThemeMode: String, Codable, CaseIterable {
    case system
    case light
    case dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    func next() -> ThemeMode {
        let all = ThemeMode.allCases
        let idx = all.firstIndex(of: self)!
        return all[(idx + 1) % all.count]
    }
}

@MainActor
final class CodeSquadState: ObservableObject {
    static let shared = CodeSquadState()

    @Published var workspaces: [Workspace] = []
    @Published var claudeStatus: [String: ClaudeStatus] = [:]
    @Published var claudeSessions: [String: [ClaudeSession]] = [:]
    @Published var panelMinimized: Bool = false
    @Published var initialScanDone: Bool = true
    @Published var themeMode: ThemeMode = .system


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
    }

    func claudeNeedsAttention(workspace: String) {
        if claudeStatus[workspace] == .permissionNeeded { return }
        claudeStatus[workspace] = .needsAttention
    }

    func claudeFinished(workspace: String) {
        let current = claudeStatus[workspace]
        if current == .working || current == .permissionNeeded {
            claudeStatus[workspace] = .needsAttention
        }
    }

    func clearStatusAndCollapse(for workspace: String) {
        let current = claudeStatus[workspace]
        if current == .needsAttention || current == .permissionNeeded {
            claudeStatus[workspace] = .idle
        }
    }

    func registerWorkspace(name: String, folderPaths: [String], workspaceFile: String? = nil) {
        if let idx = workspaces.firstIndex(where: { $0.name == name }) {
            workspaces[idx].folderPaths = folderPaths
            workspaces[idx].workspaceFile = workspaceFile
        } else {
            workspaces.append(Workspace(name: name, folderPaths: folderPaths, workspaceFile: workspaceFile))
            workspaces.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    func deregisterWorkspace(name: String) {
        workspaces.removeAll { $0.name == name }
        claudeStatus.removeValue(forKey: name)
        claudeSessions.removeValue(forKey: name)
    }
}
