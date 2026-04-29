import Foundation
import Network
import OSLog

struct HookPayload: Decodable, Sendable {
    let sessionId: String
    let cwd: String
    let hookEventName: String

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case cwd
        case hookEventName = "hook_event_name"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sessionId = try container.decode(String.self, forKey: .sessionId)
        self.cwd = try container.decode(String.self, forKey: .cwd)
        self.hookEventName = try container.decode(String.self, forKey: .hookEventName)
    }
}

struct WorkspaceRegistration: Decodable, Sendable {
    let windowId: String
    let workspaceName: String
    let folderPaths: [String]
    let claudeInstalled: Bool
}

struct WorkspaceEvent: Decodable, Sendable {
    let windowId: String
}


@MainActor
final class HookServer {
    private let port: UInt16
    private var listener: NWListener?
    private let state: CodeSquadState
    private let logger = Logger(subsystem: "com.codesquad.app", category: "HookServer")
    weak var windowDiscovery: WindowDiscovery?

    init(port: UInt16 = 9876, state: CodeSquadState) {
        self.port = port
        self.state = state
    }

    func start() {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            logger.error("Invalid port: \(self.port)")
            return
        }

        do {
            let params = NWParameters.tcp
            params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: nwPort)
            params.allowLocalEndpointReuse = true
            listener = try NWListener(using: params, on: nwPort)
        } catch {
            logger.error("Failed to create listener: \(error)")
            return
        }

        listener?.newConnectionHandler = { [weak self] connection in
            guard self?.isLoopback(connection) == true else {
                connection.cancel()
                return
            }
            DispatchQueue.main.async {
                self?.handleConnection(connection)
            }
        }

        listener?.stateUpdateHandler = { [weak self] newState in
            switch newState {
            case .ready:
                self?.logger.info("Hook server listening on 127.0.0.1:\(self?.port ?? 0)")
            case .failed(let error):
                self?.logger.error("Hook server failed: \(error)")
            default:
                break
            }
        }

        listener?.start(queue: .main)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private nonisolated func isLoopback(_ connection: NWConnection) -> Bool {
        guard case .hostPort(let host, _) = connection.currentPath?.remoteEndpoint else {
            return false
        }
        let addr = "\(host)"
        return addr == "127.0.0.1" || addr == "::1"
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        receiveHTTPRequest(on: connection)
    }

    private nonisolated func receiveHTTPRequest(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            if error != nil {
                connection.cancel()
                return
            }

            guard let data else {
                connection.cancel()
                return
            }

            let (statusCode, responseBody) = self.processHTTPRequest(data)
            self.sendHTTPResponse(on: connection, statusCode: statusCode, body: responseBody)

            if isComplete {
                connection.cancel()
            }
        }
    }

    private nonisolated func processHTTPRequest(_ data: Data) -> (Int, String) {
        guard let raw = String(data: data, encoding: .utf8) else {
            return (400, "bad request")
        }

        let lines = raw.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let requestLine = lines.first else {
            return (400, "bad request")
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            return (400, "bad request")
        }

        let method = String(parts[0])
        let path = String(parts[1])

        guard method == "POST" else {
            return (405, "method not allowed")
        }

        let hookPaths: Set = ["/hook/attention", "/hook/working", "/hook/stopped", "/hook/session-start", "/hook/session-end",
                              "/hook/permission", "/notify", "/stop"]
        let wsPaths: Set = ["/workspace/register", "/workspace/deregister", "/workspace/focus"]

        guard hookPaths.contains(path) || wsPaths.contains(path) else {
            return (404, "not found")
        }

        guard let bodyStart = raw.range(of: "\r\n\r\n") else {
            return (400, "no body")
        }

        let bodyString = String(raw[bodyStart.upperBound...])
        guard let bodyData = bodyString.data(using: .utf8) else {
            return (400, "bad body encoding")
        }

        if wsPaths.contains(path) {
            return processWorkspaceRequest(path: path, bodyData: bodyData)
        }

        let payload: HookPayload
        do {
            payload = try JSONDecoder().decode(HookPayload.self, from: bodyData)
        } catch {
            return (400, "bad payload")
        }

        DispatchQueue.main.async { [weak self, payload, path] in
            self?.routePayload(payload, path: path)
        }

        return (200, "ok")
    }

    private nonisolated func processWorkspaceRequest(path: String, bodyData: Data) -> (Int, String) {
        switch path {
        case "/workspace/register":
            guard let reg = try? JSONDecoder().decode(WorkspaceRegistration.self, from: bodyData) else {
                return (400, "bad payload")
            }
            DispatchQueue.main.async { [weak self] in
                self?.handleWorkspaceRegister(reg)
            }
        case "/workspace/deregister":
            guard let evt = try? JSONDecoder().decode(WorkspaceEvent.self, from: bodyData) else {
                return (400, "bad payload")
            }
            DispatchQueue.main.async { [weak self] in
                self?.handleWorkspaceDeregister(evt)
            }
        case "/workspace/focus":
            guard let evt = try? JSONDecoder().decode(WorkspaceEvent.self, from: bodyData) else {
                return (400, "bad payload")
            }
            DispatchQueue.main.async { [weak self] in
                self?.handleWorkspaceFocus(evt)
            }
        default:
            return (404, "not found")
        }
        return (200, "ok")
    }

    @MainActor
    private func routePayload(_ payload: HookPayload, path: String, isRetry: Bool = false) {
        let workspace = state.workspaces.first(where: { $0.matchesCWD(payload.cwd) })

        guard let workspace else {
            if !isRetry, let discovery = windowDiscovery {
                logger.info("No workspace match for cwd: \(payload.cwd, privacy: .public) — refreshing and retrying")
                discovery.refresh()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.routePayload(payload, path: path, isRetry: true)
                }
            } else {
                logger.warning("No workspace match for cwd: \(payload.cwd, privacy: .public) (after retry)")
            }
            return
        }

        let name = workspace.name
        logger.debug("\(path, privacy: .public) → \(name, privacy: .public) (session: \(payload.sessionId, privacy: .public))")

        switch path {
        case "/hook/session-start", "/hook/working":
            state.claudeWorking(workspace: name)
        case "/hook/session-end":
            state.claudeFinished(workspace: name)
        case "/hook/permission":
            state.claudePermissionNeeded(workspace: name)
        case "/hook/attention", "/notify":
            state.claudeNeedsAttention(workspace: name)
        case "/hook/stopped", "/stop":
            state.claudeFinished(workspace: name)
        default:
            break
        }
    }

    @MainActor
    private func handleWorkspaceRegister(_ reg: WorkspaceRegistration) {
        logger.debug("Extension registered: \(reg.workspaceName, privacy: .public) folders=\(reg.folderPaths.joined(separator: ", "), privacy: .public)")
        state.registerExtensionWorkspace(name: reg.workspaceName, folderPaths: reg.folderPaths)
    }

    @MainActor
    private func handleWorkspaceDeregister(_ evt: WorkspaceEvent) {
        logger.debug("Extension deregistered: windowId=\(evt.windowId, privacy: .public)")
    }

    @MainActor
    private func handleWorkspaceFocus(_ evt: WorkspaceEvent) {
        logger.debug("Extension focus: windowId=\(evt.windowId, privacy: .public)")
    }

    private nonisolated func sendHTTPResponse(on connection: NWConnection, statusCode: Int, body: String) {
        let statusText: String
        switch statusCode {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        case 405: statusText = "Method Not Allowed"
        default: statusText = "Error"
        }

        let response = "HTTP/1.1 \(statusCode) \(statusText)\r\nContent-Type: text/plain\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        let responseData = Data(response.utf8)

        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
