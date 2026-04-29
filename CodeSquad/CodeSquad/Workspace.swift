import Foundation

struct Workspace: Identifiable {
    let id: String
    let name: String
    var folderPaths: [String] = []
    var workspaceFile: String?
    var remoteAuthority: String?

    init(name: String, folderPaths: [String] = [], workspaceFile: String? = nil, remoteAuthority: String? = nil) {
        self.id = name
        self.name = name
        self.folderPaths = folderPaths
        self.workspaceFile = workspaceFile
        self.remoteAuthority = remoteAuthority
    }

    var isRemote: Bool { remoteAuthority != nil }

    static func parseWorkspaceName(from title: String) -> String {
        var cleaned = title

        let suffixes = [
            " — Visual Studio Code",
            " – Visual Studio Code",
            " — Code - Insiders",
            " – Code - Insiders",
            " — Cursor",
            " – Cursor",
        ]
        for suffix in suffixes {
            if cleaned.hasSuffix(suffix) {
                cleaned = String(cleaned.dropLast(suffix.count))
                break
            }
        }

        for separator in [" — ", " – "] {
            if let range = cleaned.range(of: separator, options: .backwards) {
                cleaned = String(cleaned[range.upperBound...])
                break
            }
        }

        cleaned = cleaned.trimmingCharacters(in: .whitespaces)

        if let parenRange = cleaned.range(of: " (", options: .backwards) {
            if cleaned.hasSuffix(")") {
                cleaned = String(cleaned[..<parenRange.lowerBound])
            }
        }
        if let bracketRange = cleaned.range(of: " [", options: .backwards) {
            if cleaned.hasSuffix("]") {
                cleaned = String(cleaned[..<bracketRange.lowerBound])
            }
        }

        return cleaned.trimmingCharacters(in: .whitespaces)
    }

    func matchesCWD(_ cwd: String) -> Bool {
        let normalizedCWD = cwd.hasSuffix("/") ? String(cwd.dropLast()) : cwd

        for folder in folderPaths {
            let normalizedFolder = folder.hasSuffix("/") ? String(folder.dropLast()) : folder
            if normalizedCWD == normalizedFolder || normalizedCWD.hasPrefix(normalizedFolder + "/") {
                return true
            }
        }

        let components = normalizedCWD.split(separator: "/").map { $0.lowercased() }
        let lowName = name.lowercased()
        guard lowName.count >= 3 else { return false }
        return components.contains(lowName)
    }
}
