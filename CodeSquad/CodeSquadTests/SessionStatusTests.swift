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
}
