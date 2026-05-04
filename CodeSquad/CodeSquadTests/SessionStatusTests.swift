import Testing
@testable import CodeSquad

@Suite("Per-session status")
struct SessionStatusTests {
    @Test("workspaceStatus returns .inactive when no sessions exist")
    @MainActor func emptyWorkspace() {
        let state = CodeSquadState()
        state.registerWorkspace(name: "test", folderPaths: ["/tmp/test"])
        #expect(state.workspaceStatus(for: "test") == .inactive)
    }

    @Test("workspaceStatus cascade: permissionNeeded wins over all")
    @MainActor func cascadePermission() {
        let state = CodeSquadState()
        state.registerWorkspace(name: "test", folderPaths: ["/tmp/test"])
        let s1 = ClaudeSession(id: "s1", pid: 1, cwd: "/tmp/test", source: "Terminal", sessionId: "s1", chatTitle: nil, metaStatus: nil)
        let s2 = ClaudeSession(id: "s2", pid: 2, cwd: "/tmp/test", source: "Terminal", sessionId: "s2", chatTitle: nil, metaStatus: nil)
        let s3 = ClaudeSession(id: "s3", pid: 3, cwd: "/tmp/test", source: "Terminal", sessionId: "s3", chatTitle: nil, metaStatus: nil)
        state.claudeSessions["test"] = [s1, s2, s3]
        state.sessionStatus["s1"] = .working
        state.sessionStatus["s2"] = .needsAttention
        state.sessionStatus["s3"] = .permissionNeeded
        #expect(state.workspaceStatus(for: "test") == .permissionNeeded)
    }

    @Test("workspaceStatus cascade: needsAttention wins over working")
    @MainActor func cascadeAttention() {
        let state = CodeSquadState()
        state.registerWorkspace(name: "test", folderPaths: ["/tmp/test"])
        let s1 = ClaudeSession(id: "s1", pid: 1, cwd: "/tmp/test", source: "Terminal", sessionId: "s1", chatTitle: nil, metaStatus: nil)
        let s2 = ClaudeSession(id: "s2", pid: 2, cwd: "/tmp/test", source: "Terminal", sessionId: "s2", chatTitle: nil, metaStatus: nil)
        state.claudeSessions["test"] = [s1, s2]
        state.sessionStatus["s1"] = .working
        state.sessionStatus["s2"] = .needsAttention
        #expect(state.workspaceStatus(for: "test") == .needsAttention)
    }

    @Test("workspaceStatus cascade: working wins over idle")
    @MainActor func cascadeWorking() {
        let state = CodeSquadState()
        state.registerWorkspace(name: "test", folderPaths: ["/tmp/test"])
        let s1 = ClaudeSession(id: "s1", pid: 1, cwd: "/tmp/test", source: "Terminal", sessionId: "s1", chatTitle: nil, metaStatus: nil)
        let s2 = ClaudeSession(id: "s2", pid: 2, cwd: "/tmp/test", source: "Terminal", sessionId: "s2", chatTitle: nil, metaStatus: nil)
        state.claudeSessions["test"] = [s1, s2]
        state.sessionStatus["s1"] = .idle
        state.sessionStatus["s2"] = .working
        #expect(state.workspaceStatus(for: "test") == .working)
    }
}

@Suite("Session clearing")
struct SessionClearingTests {
    @Test("clearAllSessions clears attention and permission, leaves working")
    @MainActor func clearAll() {
        let state = CodeSquadState()
        state.registerWorkspace(name: "test", folderPaths: ["/tmp/test"])
        let s1 = ClaudeSession(id: "s1", pid: 1, cwd: "/tmp/test", source: "Terminal", sessionId: "s1", chatTitle: nil, metaStatus: nil)
        let s2 = ClaudeSession(id: "s2", pid: 2, cwd: "/tmp/test", source: "Terminal", sessionId: "s2", chatTitle: nil, metaStatus: nil)
        let s3 = ClaudeSession(id: "s3", pid: 3, cwd: "/tmp/test", source: "Terminal", sessionId: "s3", chatTitle: nil, metaStatus: nil)
        state.claudeSessions["test"] = [s1, s2, s3]
        state.sessionStatus["s1"] = .needsAttention
        state.sessionStatus["s2"] = .permissionNeeded
        state.sessionStatus["s3"] = .working

        state.clearAllSessions(for: "test")

        #expect(state.sessionStatus["s1"] == .idle)
        #expect(state.sessionStatus["s2"] == .idle)
        #expect(state.sessionStatus["s3"] == .working)
    }

    @Test("clearSession clears only the targeted session")
    @MainActor func clearSingle() {
        let state = CodeSquadState()
        state.registerWorkspace(name: "test", folderPaths: ["/tmp/test"])
        let s1 = ClaudeSession(id: "s1", pid: 1, cwd: "/tmp/test", source: "Terminal", sessionId: "s1", chatTitle: nil, metaStatus: nil)
        let s2 = ClaudeSession(id: "s2", pid: 2, cwd: "/tmp/test", source: "Terminal", sessionId: "s2", chatTitle: nil, metaStatus: nil)
        state.claudeSessions["test"] = [s1, s2]
        state.sessionStatus["s1"] = .needsAttention
        state.sessionStatus["s2"] = .permissionNeeded

        state.clearSession(id: "s1")

        #expect(state.sessionStatus["s1"] == .idle)
        #expect(state.sessionStatus["s2"] == .permissionNeeded)
    }
}

@Suite("Session isolation")
struct SessionIsolationTests {
    @Test("Setting status on one session does not affect another")
    @MainActor func isolation() {
        let state = CodeSquadState()
        state.registerWorkspace(name: "test", folderPaths: ["/tmp/test"])
        let s1 = ClaudeSession(id: "s1", pid: 1, cwd: "/tmp/test", source: "Terminal", sessionId: "s1", chatTitle: nil, metaStatus: nil)
        let s2 = ClaudeSession(id: "s2", pid: 2, cwd: "/tmp/test", source: "Terminal", sessionId: "s2", chatTitle: nil, metaStatus: nil)
        state.claudeSessions["test"] = [s1, s2]
        state.sessionStatus["s1"] = .idle
        state.sessionStatus["s2"] = .idle

        state.claudeWorking(sessionId: "s1")

        #expect(state.sessionStatus["s1"] == .working)
        #expect(state.sessionStatus["s2"] == .idle)
    }

    @Test("attentionCount reflects per-session statuses")
    @MainActor func attentionCount() {
        let state = CodeSquadState()
        state.sessionStatus["s1"] = .needsAttention
        state.sessionStatus["s2"] = .permissionNeeded
        state.sessionStatus["s3"] = .working
        state.sessionStatus["s4"] = .idle
        #expect(state.attentionCount == 2)
    }

    @Test("deregisterWorkspace cleans up session statuses")
    @MainActor func deregisterCleansUp() {
        let state = CodeSquadState()
        state.registerWorkspace(name: "test", folderPaths: ["/tmp/test"])
        let s1 = ClaudeSession(id: "s1", pid: 1, cwd: "/tmp/test", source: "Terminal", sessionId: "s1", chatTitle: nil, metaStatus: nil)
        state.claudeSessions["test"] = [s1]
        state.sessionStatus["s1"] = .working

        state.deregisterWorkspace(name: "test")

        #expect(state.sessionStatus["s1"] == nil)
        #expect(state.claudeSessions["test"] == nil)
    }

    @Test("Hook fires before scanner: status migrates from PID to UUID ID")
    @MainActor func hookBeforeScanner() {
        let state = CodeSquadState()
        state.registerWorkspace(name: "test", folderPaths: ["/tmp/test"])

        // Scanner first discovers session with PID-based ID (no metadata yet)
        let pidSession = ClaudeSession(id: "999", pid: 999, cwd: "/tmp/test", source: "Terminal", sessionId: nil, chatTitle: nil, metaStatus: nil)
        state.claudeProcessFound(workspace: "test", sessions: [pidSession])
        #expect(state.sessionStatus["999"] == .idle)

        // Hook fires with UUID, no scanner match yet — writes to UUID key
        state.claudePermissionNeeded(sessionId: "abc-uuid")
        #expect(state.sessionStatus["abc-uuid"] == .permissionNeeded)

        // Scanner next cycle: metadata loaded, session ID transitions from PID to UUID
        let uuidSession = ClaudeSession(id: "abc-uuid", pid: 999, cwd: "/tmp/test", source: "Terminal", sessionId: "abc-uuid", chatTitle: "my task", metaStatus: nil)
        state.claudeProcessFound(workspace: "test", sessions: [uuidSession])

        // PID-based entry cleaned up, UUID entry preserves permission status
        #expect(state.sessionStatus["999"] == nil)
        #expect(state.sessionStatus["abc-uuid"] == .permissionNeeded)
    }

    @Test("remoteClaudeDetected creates synthetic session with idle status")
    @MainActor func remoteDetected() {
        let state = CodeSquadState()
        state.registerWorkspace(name: "remote-ws", folderPaths: ["/tmp/remote"])

        state.remoteClaudeDetected(workspace: "remote-ws")

        #expect(state.workspaceStatus(for: "remote-ws") == .idle)
        #expect(state.claudeSessions["remote-ws"]?.count == 1)
        #expect(state.claudeSessions["remote-ws"]?.first?.id == "remote-remote-ws")
    }

    @Test("remoteClaudeGone cleans up synthetic session")
    @MainActor func remoteGone() {
        let state = CodeSquadState()
        state.registerWorkspace(name: "remote-ws", folderPaths: ["/tmp/remote"])
        state.remoteClaudeDetected(workspace: "remote-ws")

        state.remoteClaudeGone(workspace: "remote-ws")

        #expect(state.workspaceStatus(for: "remote-ws") == .inactive)
        #expect(state.claudeSessions["remote-ws"] == nil)
    }
}
