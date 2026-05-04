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

enum ExtensionState {
    case alreadyInstalled
    case justInstalled
    case installFailed
    case vsCodeNotFound
}

@MainActor
final class CodeSquadState: ObservableObject {
    static let shared = CodeSquadState()

    @Published var workspaces: [Workspace] = []
    @Published var sessionStatus: [String: ClaudeStatus] = [:]
    @Published var claudeSessions: [String: [ClaudeSession]] = [:]
    @Published var panelMinimized: Bool = false
    @Published var themeMode: ThemeMode = .system
    @Published var extensionState: ExtensionState = .alreadyInstalled

    var remoteWorkspaces: Set<String> = []

    var attentionCount: Int {
        sessionStatus.values.filter { $0 == .needsAttention || $0 == .permissionNeeded }.count
    }

    var hasAttention: Bool {
        attentionCount > 0
    }

    func workspaceStatus(for workspace: String) -> ClaudeStatus {
        let sessions = claudeSessions[workspace] ?? []
        let statuses = sessions.compactMap { sessionStatus[$0.id] }
        if statuses.contains(.permissionNeeded) { return .permissionNeeded }
        if statuses.contains(.needsAttention) { return .needsAttention }
        if statuses.contains(.working) { return .working }
        if statuses.contains(.idle) { return .idle }
        return .inactive
    }

    func claudeProcessFound(workspace: String, sessions: [ClaudeSession]) {
        let oldSessions = claudeSessions[workspace] ?? []
        let newIDs = Set(sessions.map { $0.id })
        let newBySessionId = Dictionary(
            sessions.compactMap { s in s.sessionId.map { ($0, s.id) } },
            uniquingKeysWith: { first, _ in first }
        )

        for old in oldSessions where !newIDs.contains(old.id) {
            guard let oldStatus = sessionStatus[old.id] else { continue }
            if let sid = old.sessionId, let newId = newBySessionId[sid] {
                sessionStatus[newId] = oldStatus
                sessionStatus.removeValue(forKey: old.id)
            } else if oldStatus != .needsAttention && oldStatus != .permissionNeeded {
                sessionStatus.removeValue(forKey: old.id)
            }
        }

        claudeSessions[workspace] = sessions
        for session in sessions {
            let current = sessionStatus[session.id]
            if current == nil || current == .inactive {
                sessionStatus[session.id] = .idle
            }
        }
    }

    func claudeProcessGone(workspace: String) {
        let oldSessions = claudeSessions[workspace] ?? []
        for session in oldSessions {
            let current = sessionStatus[session.id]
            if current != .needsAttention && current != .permissionNeeded {
                sessionStatus.removeValue(forKey: session.id)
            }
        }
        claudeSessions.removeValue(forKey: workspace)
    }

    func claudeWorking(sessionId: String) {
        sessionStatus[sessionId] = .working
    }

    func claudePermissionNeeded(sessionId: String) {
        sessionStatus[sessionId] = .permissionNeeded
    }

    func claudeNeedsAttention(sessionId: String) {
        let current = sessionStatus[sessionId]
        if current == .working || current == .permissionNeeded {
            sessionStatus[sessionId] = .needsAttention
        }
    }

    func claudeFinished(sessionId: String) {
        let current = sessionStatus[sessionId]
        if current == .working || current == .permissionNeeded {
            sessionStatus[sessionId] = .needsAttention
        }
    }

    func clearAllSessions(for workspace: String) {
        let sessions = claudeSessions[workspace] ?? []
        for session in sessions {
            let current = sessionStatus[session.id]
            if current == .needsAttention || current == .permissionNeeded {
                sessionStatus[session.id] = .idle
            }
        }
    }

    func clearSession(id: String) {
        let current = sessionStatus[id]
        if current == .needsAttention || current == .permissionNeeded {
            sessionStatus[id] = .idle
        }
    }

    func registerWorkspace(name: String, folderPaths: [String], workspaceFile: String? = nil, remoteAuthority: String? = nil) {
        if remoteAuthority != nil {
            remoteWorkspaces.insert(name)
        } else {
            remoteWorkspaces.remove(name)
        }
        if let idx = workspaces.firstIndex(where: { $0.name == name }) {
            workspaces[idx].folderPaths = folderPaths
            workspaces[idx].workspaceFile = workspaceFile
            workspaces[idx].remoteAuthority = remoteAuthority
        } else {
            workspaces.append(Workspace(name: name, folderPaths: folderPaths, workspaceFile: workspaceFile, remoteAuthority: remoteAuthority))
            workspaces.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    func deregisterWorkspace(name: String) {
        let oldSessions = claudeSessions[name] ?? []
        for session in oldSessions {
            sessionStatus.removeValue(forKey: session.id)
        }
        workspaces.removeAll { $0.name == name }
        claudeSessions.removeValue(forKey: name)
        remoteWorkspaces.remove(name)
    }

    func remoteClaudeDetected(workspace: String) {
        let syntheticId = "remote-\(workspace)"
        if claudeSessions[workspace]?.contains(where: { $0.id == syntheticId }) != true {
            let session = ClaudeSession(
                id: syntheticId, pid: 0, cwd: "", source: "Remote",
                sessionId: nil, chatTitle: nil, metaStatus: nil
            )
            claudeSessions[workspace, default: []].append(session)
        }
        let current = sessionStatus[syntheticId]
        if current == nil || current == .inactive {
            sessionStatus[syntheticId] = .idle
        }
    }

    func remoteClaudeGone(workspace: String) {
        let oldSessions = claudeSessions[workspace] ?? []
        for session in oldSessions {
            let current = sessionStatus[session.id]
            if current != .needsAttention && current != .permissionNeeded {
                sessionStatus.removeValue(forKey: session.id)
            }
        }
        claudeSessions.removeValue(forKey: workspace)
    }
}
