import Foundation
import OSLog

struct PersistedState: Codable {
    var panelX: Double?
    var panelY: Double?
    var hooksInstalled: Bool

    init(panelX: Double? = nil, panelY: Double? = nil, hooksInstalled: Bool = false) {
        self.panelX = panelX
        self.panelY = panelY
        self.hooksInstalled = hooksInstalled
    }
}

enum StatePersistence {
    private static let logger = Logger(subsystem: "com.cdolan.conductor", category: "StatePersistence")

    static var defaultPath: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Conductor/state.json").path
    }

    static func load(from path: String? = nil) -> PersistedState {
        let filePath = path ?? defaultPath
        guard let data = FileManager.default.contents(atPath: filePath) else {
            return PersistedState()
        }
        do {
            return try JSONDecoder().decode(PersistedState.self, from: data)
        } catch {
            logger.error("Failed to decode state: \(error)")
            return PersistedState()
        }
    }

    static func save(_ state: PersistedState, to path: String? = nil) throws {
        let filePath = path ?? defaultPath
        let url = URL(fileURLWithPath: filePath)
        let dir = url.deletingLastPathComponent().path

        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(state)
        try data.write(to: url)
    }
}
