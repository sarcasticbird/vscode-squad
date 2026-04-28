import Foundation
import Darwin
import OSLog

struct ClaudeSession: Identifiable, Sendable {
    let id: String
    let pid: pid_t
    let cwd: String
    let source: String
    let sessionId: String?
    let chatTitle: String?
    let metaStatus: String?
}

private struct SessionMeta {
    let sessionId: String?
    let entrypoint: String?
    let chatTitle: String?
    let status: String?
    let cwd: String?
}

@MainActor
final class ClaudeProcessScanner {
    private let state: CodeSquadState
    private let logger = Logger(subsystem: "com.cdolan.codesquad", category: "ClaudeScanner")
    private var timer: Timer?

    init(state: CodeSquadState) {
        self.state = state
    }

    func start() {
        scan()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scan()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func scan() {
        let sessions = Self.findAllClaudeSessions()
        logger.debug("Scan found \(sessions.count) Claude session(s)")
        updateState(with: sessions)
    }

    private func updateState(with sessions: [ClaudeSession]) {
        var matched: [String: [ClaudeSession]] = [:]

        for session in sessions {
            if let workspace = state.workspaces.first(where: { $0.matchesCWD(session.cwd) }) {
                matched[workspace.name, default: []].append(session)
            }
        }

        for workspace in state.workspaces {
            if let sessions = matched[workspace.name] {
                state.claudeProcessFound(workspace: workspace.name, sessions: sessions)
                applyMetaStatus(workspace: workspace.name, sessions: sessions)
            } else {
                state.claudeProcessGone(workspace: workspace.name)
            }
        }
    }


    private func applyMetaStatus(workspace: String, sessions: [ClaudeSession]) {
        let current = state.claudeStatus[workspace]
        if current == .needsAttention || current == .working { return }

        if sessions.contains(where: { $0.metaStatus == "busy" }) {
            state.claudeStatus[workspace] = .working
        }
    }

    private nonisolated static func findAllClaudeSessions() -> [ClaudeSession] {
        let allPIDs = listAllPIDs()
        var results: [ClaudeSession] = []

        for pid in allPIDs {
            guard let execPath = processPath(for: pid) else { continue }
            let name = (execPath as NSString).lastPathComponent
            guard name == "claude" else { continue }

            let osCWD = processCWD(for: pid)
            let usableOsCWD = (osCWD != nil && !osCWD!.isEmpty && osCWD != "/") ? osCWD : nil

            let meta = readSessionMeta(for: pid, cwd: usableOsCWD)
            let cwd = usableOsCWD ?? meta?.cwd
            guard let cwd, !cwd.isEmpty, cwd != "/" else { continue }

            let source = meta?.entrypoint == "claude-vscode" ? "VS Code"
                : execPath.contains("native-binary") ? "VS Code"
                : "Terminal"

            results.append(ClaudeSession(
                id: "\(pid)", pid: pid, cwd: cwd, source: source,
                sessionId: meta?.sessionId, chatTitle: meta?.chatTitle,
                metaStatus: meta?.status
            ))
        }

        return results
    }

    private nonisolated static func readSessionMeta(for pid: pid_t, cwd: String?) -> SessionMeta? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let metaPath = "\(home)/.claude/sessions/\(pid).json"

        guard let data = FileManager.default.contents(atPath: metaPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let sessionId = json["sessionId"] as? String
        let entrypoint = json["entrypoint"] as? String
        let status = json["status"] as? String
        let metaCWD = json["cwd"] as? String

        let effectiveCWD = cwd ?? metaCWD
        var chatTitle: String?
        if let sessionId, let effectiveCWD {
            chatTitle = readChatTitle(sessionId: sessionId, cwd: effectiveCWD)
        }

        return SessionMeta(sessionId: sessionId, entrypoint: entrypoint, chatTitle: chatTitle, status: status, cwd: metaCWD)
    }

    private nonisolated static func readChatTitle(sessionId: String, cwd: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let projectKey = cwd.replacingOccurrences(of: "/", with: "-")
        let jsonlPath = "\(home)/.claude/projects/\(projectKey)/\(sessionId).jsonl"

        guard let handle = FileHandle(forReadingAtPath: jsonlPath) else { return nil }
        defer { handle.closeFile() }

        // Read first 32KB to find first user message
        let chunk = handle.readData(ofLength: 32768)
        guard let text = String(data: chunk, encoding: .utf8) else { return nil }

        for line in text.components(separatedBy: "\n") {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  obj["type"] as? String == "user",
                  let message = obj["message"] as? [String: Any] else {
                continue
            }

            let content = message["content"]
            var userText: String?
            if let s = content as? String {
                userText = s
            } else if let arr = content as? [[String: Any]] {
                userText = arr.first(where: { $0["type"] as? String == "text" })?["text"] as? String
            }

            guard let userText, !userText.hasPrefix("<"), userText.count > 5 else { continue }

            let firstLine = userText.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: "\n").first ?? ""
            return String(firstLine.prefix(60))
        }

        return nil
    }

    private nonisolated static func listAllPIDs() -> [pid_t] {
        var count = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard count > 0 else { return [] }

        var pids = [pid_t](repeating: 0, count: Int(count) / MemoryLayout<pid_t>.size + 16)
        count = pids.withUnsafeMutableBufferPointer { buf in
            proc_listpids(UInt32(PROC_ALL_PIDS), 0, buf.baseAddress, Int32(buf.count * MemoryLayout<pid_t>.size))
        }

        let actualCount = Int(count) / MemoryLayout<pid_t>.size
        return Array(pids.prefix(actualCount)).filter { $0 > 0 }
    }

    private nonisolated static func processPath(for pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let result = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard result > 0 else { return nil }
        let len = buffer.firstIndex(of: 0) ?? buffer.count
        return String(decoding: buffer.prefix(len).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private nonisolated static func parentPID(of pid: pid_t) -> pid_t? {
        var info = proc_bsdshortinfo()
        let size = Int32(MemoryLayout<proc_bsdshortinfo>.size)
        let result = proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &info, size)
        guard result > 0 else { return nil }
        let ppid = pid_t(info.pbsi_ppid)
        return ppid > 0 ? ppid : nil
    }

    private nonisolated static func processCWD(for pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        let result = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size)
        guard result == size else { return nil }

        return withUnsafePointer(to: &info.pvi_cdir.vip_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { cStr in
                String(cString: cStr)
            }
        }
    }
}
