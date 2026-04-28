import SwiftUI
import ApplicationServices

@MainActor
struct PanelContentView: View {
    @ObservedObject var state: ConductorState

    @State private var hoverTask: Task<Void, Never>?

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
                hoverTask = Task { @MainActor in
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

@MainActor
struct WorkspaceRow: View {
    let workspace: Workspace
    let isBadged: Bool
    let onTap: @MainActor () -> Void

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
