import Foundation
import OSLog

enum HookInstaller {
    private static let logger = Logger(subsystem: "com.cdolan.codesquad", category: "HookInstaller")

    static let baseURL = "http://127.0.0.1:9876"

    static let requiredHooks: [(event: String, path: String, matcher: String?)] = [
        ("Notification", "/hook/attention", "permission_prompt|idle_prompt"),
        ("PermissionRequest", "/hook/permission", nil),
        ("PreToolUse", "/hook/working", nil),
        ("UserPromptSubmit", "/hook/working", nil),
        ("Stop", "/hook/stopped", nil),
        ("SessionStart", "/hook/session-start", nil),
        ("SessionEnd", "/hook/session-end", nil),
    ]

    static var settingsPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.claude/settings.json"
    }

    static func hooksPresent(in data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return false
        }

        return requiredHooks.allSatisfy { hookDef in
            hookArrayContainsURL(hooks[hookDef.event], url: "\(baseURL)\(hookDef.path)")
        }
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

        for hookDef in requiredHooks {
            let url = "\(baseURL)\(hookDef.path)"
            if !hookArrayContainsURL(hooks[hookDef.event], url: url) {
                var httpHook: [String: Any] = ["type": "http", "url": url]
                httpHook["async"] = true
                var entry: [String: Any] = ["hooks": [httpHook]]
                if let matcher = hookDef.matcher {
                    entry["matcher"] = matcher
                }
                var existing = (hooks[hookDef.event] as? [[String: Any]]) ?? []
                existing.append(entry)
                hooks[hookDef.event] = existing
            }
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
