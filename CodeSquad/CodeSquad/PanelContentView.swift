import SwiftUI
import ApplicationServices

@MainActor
struct PanelContentView: View {
    @ObservedObject var state: CodeSquadState

    var body: some View {
        Group {
            if state.panelMinimized {
                minimizedBar
            } else {
                rosterView
            }
        }
        .contextMenu {
            Button("Quit CodeSquad") {
                NSApp.terminate(nil)
            }
        }
    }

    private var minimizedBar: some View {
        HStack(spacing: 6) {
            Text("CodeSquad")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))

            if state.hasAttention {
                Text("\(state.attentionCount)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
            }

            Spacer()

            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
                .onTapGesture { state.toggleMinimized() }

            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
                .onTapGesture { NSApp.terminate(nil) }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.black.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                )
        )
    }

    private var rosterView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("CodeSquad")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))

                Spacer()

                Image(systemName: "chevron.up")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
                    .onTapGesture { state.toggleMinimized() }

                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
                    .onTapGesture { NSApp.terminate(nil) }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            if !state.initialScanDone {
                Spacer()
            } else if !state.axTrusted {
                VStack(spacing: 6) {
                    Text("Accessibility permission needed")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange)
                    Text("Open System Settings")
                        .font(.system(size: 11))
                        .foregroundStyle(.blue)
                        .onTapGesture {
                            NSWorkspace.shared.open(
                                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                            )
                        }
                }
                .padding(12)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(state.workspaces) { workspace in
                            WorkspaceCard(
                                workspace: workspace,
                                claudeStatus: state.claudeStatus[workspace.name] ?? .inactive,
                                sessions: state.claudeSessions[workspace.name] ?? [],
                                onTap: { focusWorkspace(workspace) }
                            )
                        }

                        if !state.terminalSessions.isEmpty {
                            Text("Terminal")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.35))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 4)
                                .padding(.top, 6)

                            ForEach(state.terminalSessions) { session in
                                WorkspaceCard(
                                    workspace: session,
                                    claudeStatus: state.claudeStatus[session.name] ?? .inactive,
                                    sessions: state.claudeSessions[session.name] ?? [],
                                    onTap: {}
                                )
                            }
                        }

                        if state.workspaces.isEmpty && state.terminalSessions.isEmpty {
                            Text("No VS Code windows detected")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.4))
                                .padding(12)
                        }
                    }
                    .padding(.horizontal, 8)
                }
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

        state.clearStatusAndCollapse(for: workspace.name)
    }
}

@MainActor
struct WorkspaceCard: View {
    let workspace: Workspace
    let claudeStatus: ClaudeStatus
    let sessions: [ClaudeSession]
    let onTap: @MainActor () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                statusDot
                    .frame(width: 8, height: 8)

                Text(workspace.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if sessions.count > 1 {
                    Text("×\(sessions.count)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                }

                Spacer()

                if claudeStatus == .needsAttention {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 10, height: 10)
                }
            }

            Text(workspace.title)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.4))
                .lineLimit(1)
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
        case .needsAttention:
            Circle().fill(.orange)
        case .idle:
            Circle().fill(.cyan.opacity(0.7))
        case .inactive:
            Circle().fill(.white.opacity(0.15))
        }
    }

    private var sessionColor: Color {
        switch claudeStatus {
        case .working: return .green.opacity(0.6)
        case .needsAttention: return .orange.opacity(0.7)
        case .idle: return .cyan.opacity(0.6)
        case .inactive: return .white.opacity(0.3)
        }
    }

    private func sessionLabel(_ session: ClaudeSession) -> String {
        let icon = session.source == "VS Code" ? "VS Code" : "CLI"
        if let title = session.chatTitle, !title.isEmpty {
            return "\(icon): \(title)"
        }
        return icon
    }

    private var cardBackground: Color {
        if claudeStatus == .needsAttention {
            return .orange.opacity(0.15)
        } else if isHovered {
            return .white.opacity(0.08)
        } else {
            return .white.opacity(0.04)
        }
    }
}
