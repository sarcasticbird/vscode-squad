import SwiftUI

@MainActor
struct PanelContentView: View {
    @ObservedObject var state: CodeSquadState
    @Environment(\.colorScheme) private var colorScheme

    private var panel: PanelColors { PanelColors(colorScheme) }

    var body: some View {
        Group {
            if state.panelMinimized {
                minimizedBar
            } else {
                rosterView
            }
        }
        .preferredColorScheme(state.themeMode.colorScheme)
        .contextMenu {
            Button("Quit CodeSquad") {
                NSApp.terminate(nil)
            }
        }
    }

    private var minimizedBar: some View {
        HStack(spacing: 4) {
            ForEach(state.workspaces) { ws in
                let status = state.claudeStatus[ws.name] ?? .inactive
                HStack(spacing: 3) {
                    Circle()
                        .fill(dotColor(for: status))
                        .frame(width: 6, height: 6)
                    Text(ws.name)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(panel.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(minWidth: 14, alignment: .leading)
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(status == .needsAttention || status == .permissionNeeded
                              ? Color.orange.opacity(0.15) : panel.cardDefault)
                )
                .onTapGesture { focusWorkspace(ws) }
            }

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(panel.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(panel.border, lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .highPriorityGesture(TapGesture(count: 2).onEnded { state.panelMinimized = false })
    }

    private func dotColor(for status: ClaudeStatus) -> Color {
        switch status {
        case .working: return .green
        case .permissionNeeded: return .purple
        case .needsAttention: return .orange
        case .idle: return .cyan.opacity(0.7)
        case .inactive: return panel.inactiveDot
        }
    }


    private var rosterView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("CodeSquad")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(panel.secondaryText)

                Spacer()

                HStack(spacing: 2) {
                    Image(systemName: state.themeMode.icon)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(panel.tertiaryText)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                        .onTapGesture { state.themeMode = state.themeMode.next() }

                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(panel.tertiaryText)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                        .onTapGesture { NSApp.terminate(nil) }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { state.panelMinimized = true }

            if state.workspaces.isEmpty {
                VStack(spacing: 6) {
                    Text("Waiting for VS Code…")
                        .font(.system(size: 11))
                        .foregroundStyle(panel.tertiaryText)
                    Text("If VS Code is already open, reload the window")
                        .font(.system(size: 9))
                        .foregroundStyle(panel.tertiaryText.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geo in
                    let useGrid = geo.size.width >= 480
                    ScrollView {
                        if useGrid {
                            LazyVGrid(columns: gridColumns(for: geo.size.width), spacing: 4) {
                                workspaceCards
                            }
                            .padding(.horizontal, 8)
                        } else {
                            VStack(spacing: 4) {
                                workspaceCards
                            }
                            .padding(.horizontal, 8)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(panel.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(panel.border, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var workspaceCards: some View {
        ForEach(state.workspaces) { workspace in
            WorkspaceCard(
                workspace: workspace,
                claudeStatus: state.claudeStatus[workspace.name] ?? .inactive,
                sessions: state.claudeSessions[workspace.name] ?? [],
                onTap: { focusWorkspace(workspace) }
            )
        }

        if state.workspaces.isEmpty {
            Text("No VS Code windows detected")
                .font(.system(size: 11))
                .foregroundStyle(panel.tertiaryText)
                .padding(12)
        }
    }

    private func gridColumns(for width: CGFloat) -> [GridItem] {
        let minCardWidth: CGFloat = 220
        let count = max(2, Int(width / minCardWidth))
        return Array(repeating: GridItem(.flexible(), spacing: 4), count: count)
    }

    private static let editorBundleIDs = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92",
    ]

    private func focusWorkspace(_ workspace: Workspace) {
        let target = workspace.workspaceFile ?? workspace.folderPaths.first
        if let path = target {
            let url = URL(fileURLWithPath: path)
            let appURL = Self.editorBundleIDs.lazy
                .compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
                .first
            if let appURL {
                NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
            } else {
                NSWorkspace.shared.open(url)
            }
        }
        state.clearStatusAndCollapse(for: workspace.name)
    }
}

struct PanelColors {
    let colorScheme: ColorScheme

    init(_ colorScheme: ColorScheme) {
        self.colorScheme = colorScheme
    }

    var isDark: Bool { colorScheme == .dark }

    var background: Color {
        isDark ? .black.opacity(0.85) : .white.opacity(0.92)
    }

    var border: Color {
        isDark ? .white.opacity(0.15) : .black.opacity(0.12)
    }

    var primaryText: Color {
        isDark ? .white : .black
    }

    var secondaryText: Color {
        isDark ? .white.opacity(0.5) : .black.opacity(0.5)
    }

    var tertiaryText: Color {
        isDark ? .white.opacity(0.4) : .black.opacity(0.35)
    }

    var cardHover: Color {
        isDark ? .white.opacity(0.08) : .black.opacity(0.06)
    }

    var cardDefault: Color {
        isDark ? .white.opacity(0.04) : .black.opacity(0.03)
    }

    var inactiveDot: Color {
        isDark ? .white.opacity(0.15) : .black.opacity(0.12)
    }
}

@MainActor
struct WorkspaceCard: View {
    let workspace: Workspace
    let claudeStatus: ClaudeStatus
    let sessions: [ClaudeSession]
    let onTap: @MainActor () -> Void

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    private var panel: PanelColors { PanelColors(colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                statusDot
                    .frame(width: 8, height: 8)

                Text(workspace.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(panel.primaryText)
                    .lineLimit(1)

                if sessions.count > 1 {
                    Text("×\(sessions.count)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(panel.tertiaryText)
                }

                Spacer()

                if claudeStatus == .permissionNeeded {
                    Circle()
                        .fill(Color.purple)
                        .frame(width: 10, height: 10)
                } else if claudeStatus == .needsAttention {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 10, height: 10)
                }
            }

            Text(workspace.folderPaths.first ?? workspace.name)
                .font(.system(size: 10))
                .foregroundStyle(panel.tertiaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.leading, 14)

            if !sessions.isEmpty {
                ForEach(sessions) { session in
                    Text(session.chatTitle ?? "Claude Code")
                        .font(.system(size: 10))
                        .foregroundStyle(sessionColor)
                        .lineLimit(1)
                        .padding(.leading, 14)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(cardBackground)
        )
        .onHover { isHovered = $0 }
        .onTapGesture { onTap() }
    }

    @ViewBuilder
    private var statusDot: some View {
        switch claudeStatus {
        case .working:
            Circle().fill(.green)
        case .permissionNeeded:
            Circle().fill(.purple)
        case .needsAttention:
            Circle().fill(.orange)
        case .idle:
            Circle().fill(.cyan.opacity(0.7))
        case .inactive:
            Circle().fill(panel.inactiveDot)
        }
    }

    private var sessionColor: Color {
        switch claudeStatus {
        case .working: return .green.opacity(0.6)
        case .permissionNeeded: return .purple.opacity(0.7)
        case .needsAttention: return .orange.opacity(0.7)
        case .idle: return .cyan.opacity(0.6)
        case .inactive: return panel.tertiaryText
        }
    }

    private var cardBackground: Color {
        if claudeStatus == .permissionNeeded {
            return .purple.opacity(0.15)
        } else if claudeStatus == .needsAttention {
            return .orange.opacity(0.15)
        } else if isHovered {
            return panel.cardHover
        } else {
            return panel.cardDefault
        }
    }
}
