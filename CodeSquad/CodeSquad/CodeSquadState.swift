import Foundation
import Combine
import ApplicationServices

enum ClaudeStatus: Equatable {
    case inactive
    case idle
    case working
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

    var attentionCount: Int {
        claudeStatus.values.filter { $0 == .needsAttention }.count
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
        claudeStatus[workspace] = .inactive
    }

    func claudeWorking(workspace: String) {
        if claudeStatus[workspace] != .needsAttention {
            claudeStatus[workspace] = .working
        }
    }

    func claudeNeedsAttention(workspace: String) {
        claudeStatus[workspace] = .needsAttention
        panelMinimized = false
    }

    func claudeFinished(workspace: String) {
        let current = claudeStatus[workspace]
        if current == .working {
            claudeStatus[workspace] = .needsAttention
            panelMinimized = false
        }
    }

    func clearStatusAndCollapse(for workspace: String) {
        if claudeStatus[workspace] == .needsAttention {
            claudeStatus[workspace] = .idle
        }
    }

    func toggleMinimized() {
        panelMinimized.toggle()
    }

    func refreshAXStatus() {
        axTrusted = AXIsProcessTrusted()
    }
}
