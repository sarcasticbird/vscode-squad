import Testing
@testable import CodeSquad

@Suite("Workspace title parsing")
struct WorkspaceTitleParsingTests {
    @Test("Extracts workspace from 'file — project' format")
    func fileAndProject() {
        let name = Workspace.parseWorkspaceName(
            from: "main.swift — Conductor — Visual Studio Code"
        )
        #expect(name == "Conductor")
    }

    @Test("Extracts workspace from 'project — Visual Studio Code' format")
    func projectOnly() {
        let name = Workspace.parseWorkspaceName(
            from: "Conductor — Visual Studio Code"
        )
        #expect(name == "Conductor")
    }

    @Test("Strips Cursor suffix")
    func cursorSuffix() {
        let name = Workspace.parseWorkspaceName(
            from: "main.swift — MyProject — Cursor"
        )
        #expect(name == "MyProject")
    }

    @Test("Strips Code - Insiders suffix")
    func insidersSuffix() {
        let name = Workspace.parseWorkspaceName(
            from: "index.ts — webapp — Code - Insiders"
        )
        #expect(name == "webapp")
    }

    @Test("Returns full title when no separator found")
    func noSeparator() {
        let name = Workspace.parseWorkspaceName(from: "Welcome")
        #expect(name == "Welcome")
    }

    @Test("Handles em-dash and en-dash")
    func dashVariants() {
        let em = Workspace.parseWorkspaceName(from: "file.py — myproject — Visual Studio Code")
        let en = Workspace.parseWorkspaceName(from: "file.py – myproject – Visual Studio Code")
        #expect(em == "myproject")
        #expect(en == "myproject")
    }
}

@Suite("Workspace CWD matching")
struct WorkspaceCWDMatchingTests {
    @Test("Matches by basename")
    func basenameMatch() {
        let ws = Workspace(name: "vscode-squad", title: "test — vscode-squad", pid: 0, windowElement: nil)
        #expect(ws.matchesCWD("/Users/cdolan/Projects/vscode-squad"))
    }

    @Test("Does not match unrelated path")
    func noMatch() {
        let ws = Workspace(name: "vscode-squad", title: "test — vscode-squad", pid: 0, windowElement: nil)
        #expect(!ws.matchesCWD("/Users/cdolan/Projects/other-project"))
    }

    @Test("Matches when workspace name appears in path")
    func substringMatch() {
        let ws = Workspace(name: "feature", title: "test — feature", pid: 0, windowElement: nil)
        #expect(ws.matchesCWD("/Users/cdolan/Projects/repo-a/feature"))
    }

    @Test("Handles trailing slash in cwd")
    func trailingSlash() {
        let ws = Workspace(name: "vscode-squad", title: "test", pid: 0, windowElement: nil)
        #expect(ws.matchesCWD("/Users/cdolan/Projects/vscode-squad/"))
    }
}
