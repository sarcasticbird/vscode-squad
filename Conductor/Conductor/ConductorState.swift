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
