import ApplicationServices

struct Workspace: Identifiable {
    let id: String
    let name: String
    let title: String
    let pid: pid_t
    let windowElement: AXUIElement?

    init(name: String, title: String, pid: pid_t, windowElement: AXUIElement?) {
        self.id = "\(pid)-\(name)"
        self.name = name
        self.title = title
        self.pid = pid
        self.windowElement = windowElement
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
                return String(cleaned[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
        }

        return cleaned.trimmingCharacters(in: .whitespaces)
    }

    func matchesCWD(_ cwd: String) -> Bool {
        let normalizedCWD = cwd.hasSuffix("/") ? String(cwd.dropLast()) : cwd
        let basename = normalizedCWD.split(separator: "/").last.map(String.init) ?? normalizedCWD

        if name == basename {
            return true
        }

        if normalizedCWD.contains(name) {
            return true
        }

        return false
    }
}
