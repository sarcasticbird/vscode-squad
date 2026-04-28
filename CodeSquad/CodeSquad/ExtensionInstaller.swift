import Foundation
import OSLog

enum ExtensionInstaller {
    private static let logger = Logger(subsystem: "com.cdolan.codesquad", category: "ExtensionInstaller")

    static let extensionPrefix = "codesquad-shim-"
    static let sourcePath = NSHomeDirectory() + "/Projects/vscode-squad/CodeSquadExtension"

    static var currentVersion: String? {
        let packagePath = sourcePath + "/package.json"
        guard let data = FileManager.default.contents(atPath: packagePath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = json["version"] as? String else {
            return nil
        }
        return version
    }

    static var extensionName: String {
        extensionPrefix + (currentVersion ?? "0.0.0")
    }

    static var extensionDirs: [String] {
        let home = NSHomeDirectory()
        return [
            home + "/.vscode/extensions",
            home + "/.vscode-insiders/extensions",
            home + "/.cursor/extensions",
        ]
    }

    static func checkInstalled() -> Bool {
        extensionDirs.contains { dir in
            let path = dir + "/" + extensionName
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        }
    }

    static func install() throws {
        let fm = FileManager.default

        guard fm.fileExists(atPath: sourcePath) else {
            logger.error("Extension source not found at \(sourcePath, privacy: .public)")
            return
        }

        for dir in extensionDirs {
            guard fm.fileExists(atPath: dir) else { continue }

            removeStaleVersions(in: dir)

            let target = dir + "/" + extensionName
            if fm.fileExists(atPath: target) { continue }

            try fm.createSymbolicLink(atPath: target, withDestinationPath: sourcePath)
            logger.info("Extension symlinked: \(target, privacy: .public) → \(sourcePath, privacy: .public)")
        }
    }

    private static func removeStaleVersions(in dir: String) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return }

        let current = extensionName
        for entry in entries where entry.hasPrefix(extensionPrefix) && entry != current {
            let path = dir + "/" + entry
            do {
                try fm.removeItem(atPath: path)
                logger.info("Removed stale extension: \(path, privacy: .public)")
            } catch {
                logger.warning("Failed to remove stale extension \(path, privacy: .public): \(error)")
            }
        }
    }
}
