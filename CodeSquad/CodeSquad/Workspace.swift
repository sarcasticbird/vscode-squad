import ApplicationServices

struct Workspace: Identifiable {
    let id: String
    let name: String
    let title: String
    let pid: pid_t
    let windowElement: AXUIElement?
    var folderPaths: [String] = []

    init(name: String, title: String, pid: pid_t, windowElement: AXUIElement?) {
        self.id = "\(pid)-\(name)"
        self.name = name
        self.title = Self.cleanTitle(title, workspaceName: name)
        self.pid = pid
        self.windowElement = windowElement
    }

    private static func cleanTitle(_ title: String, workspaceName: String) -> String {
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

        // Strip " — WorkspaceName (Workspace)" or " — WorkspaceName" from the end
        for sep in [" — ", " – "] {
            if let range = cleaned.range(of: sep, options: .backwards) {
                let after = String(cleaned[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                var afterBase = after
                if let p = afterBase.range(of: " (", options: .backwards), afterBase.hasSuffix(")") {
                    afterBase = String(afterBase[..<p.lowerBound])
                }
                if afterBase.lowercased() == workspaceName.lowercased() {
                    cleaned = String(cleaned[..<range.lowerBound])
                    break
                }
            }
        }

        return cleaned.trimmingCharacters(in: .whitespaces)
    }

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

        // Strip VS Code decorations like " (Workspace)", " [SSH: host]"
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
        let components = normalizedCWD.split(separator: "/").map(String.init)

        if components.contains(name) {
            return true
        }

        let lowName = name.lowercased()
        let lowCWD = normalizedCWD.lowercased()
        if lowCWD.contains(lowName) {
            return true
        }

        for folder in folderPaths {
            let normalizedFolder = folder.hasSuffix("/") ? String(folder.dropLast()) : folder
            if normalizedCWD == normalizedFolder || normalizedCWD.hasPrefix(normalizedFolder + "/") {
                return true
            }
        }

        return false
    }
}
