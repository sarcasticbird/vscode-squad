import Foundation
import OSLog

enum HookInstaller {
    private static let logger = Logger(subsystem: "com.cdolan.conductor", category: "HookInstaller")

    static let conductorNotifyURL = "http://127.0.0.1:9876/notify"
    static let conductorStopURL = "http://127.0.0.1:9876/stop"

    static var settingsPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.claude/settings.json"
    }

    static func hooksPresent(in data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return false
        }

        let hasNotify = hookArrayContainsURL(hooks["Notification"], url: conductorNotifyURL)
        let hasStop = hookArrayContainsURL(hooks["Stop"], url: conductorStopURL)
        return hasNotify && hasStop
    }

    static func checkInstalled() -> Bool {
        guard let data = FileManager.default.contents(atPath: settingsPath) else {
            return false
        }
        return hooksPresent(in: data)
    }

    static func install() throws {
        let fileManager = FileManager.default
        let settingsURL = URL(fileURLWithPath: settingsPath)

        let existingData: Data
        if fileManager.fileExists(atPath: settingsPath) {
            existingData = try Data(contentsOf: settingsURL)
            let backupPath = settingsPath + ".backup.\(Int(Date().timeIntervalSince1970))"
            try fileManager.copyItem(atPath: settingsPath, toPath: backupPath)
            logger.info("Backed up settings to \(backupPath)")
        } else {
            existingData = Data("{}".utf8)
            let dir = settingsURL.deletingLastPathComponent().path
            try fileManager.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        let merged = try mergeHooks(into: existingData)
        try merged.write(to: settingsURL)
        logger.info("Hooks installed to \(settingsPath)")
    }

    static func mergeHooks(into existingData: Data) throws -> Data {
        var json = (try? JSONSerialization.jsonObject(with: existingData) as? [String: Any]) ?? [:]
        var hooks = (json["hooks"] as? [String: Any]) ?? [:]

        let notifyHook: [String: Any] = ["type": "http", "url": conductorNotifyURL]
        let stopHook: [String: Any] = ["type": "http", "url": conductorStopURL]

        if !hookArrayContainsURL(hooks["Notification"], url: conductorNotifyURL) {
            var existing = (hooks["Notification"] as? [[String: Any]]) ?? []
            existing.append(["hooks": [notifyHook]])
            hooks["Notification"] = existing
        }

        if !hookArrayContainsURL(hooks["Stop"], url: conductorStopURL) {
            var existing = (hooks["Stop"] as? [[String: Any]]) ?? []
            existing.append(["hooks": [stopHook]])
            hooks["Stop"] = existing
        }

        json["hooks"] = hooks
        return try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
    }

    private static func hookArrayContainsURL(_ value: Any?, url: String) -> Bool {
        guard let entries = value as? [[String: Any]] else { return false }
        for entry in entries {
            guard let hooks = entry["hooks"] as? [[String: Any]] else { continue }
            for hook in hooks {
                if hook["type"] as? String == "http", hook["url"] as? String == url {
                    return true
                }
            }
        }
        return false
    }
}
