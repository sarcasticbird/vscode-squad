import Testing
import Foundation
@testable import Conductor

@Suite("HookInstaller")
struct HookInstallerTests {

    @Test("Detects hooks are missing in empty settings")
    func missingInEmpty() throws {
        let json: [String: Any] = [:]
        let data = try JSONSerialization.data(withJSONObject: json)
        #expect(!HookInstaller.hooksPresent(in: data))
    }

    @Test("Detects hooks are present")
    func hooksPresent() throws {
        let settings: [String: Any] = [
            "hooks": [
                "Notification": [
                    ["hooks": [["type": "http", "url": "http://127.0.0.1:9876/notify"]]]
                ],
                "Stop": [
                    ["hooks": [["type": "http", "url": "http://127.0.0.1:9876/stop"]]]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: settings)
        #expect(HookInstaller.hooksPresent(in: data))
    }

    @Test("Merges hooks into existing settings without clobbering")
    func mergesWithoutClobbering() throws {
        let existing: [String: Any] = [
            "permissions": ["allow": ["Read"]],
            "hooks": [
                "PreToolUse": [
                    ["hooks": [["type": "command", "command": "echo hello"]]]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: existing)
        let merged = try HookInstaller.mergeHooks(into: data)
        let result = try JSONSerialization.jsonObject(with: merged) as! [String: Any]

        let permissions = result["permissions"] as? [String: Any]
        #expect(permissions != nil)

        let hooks = result["hooks"] as! [String: Any]
        #expect(hooks["PreToolUse"] != nil)
        #expect(hooks["Notification"] != nil)
        #expect(hooks["Stop"] != nil)
    }

    @Test("Creates settings from scratch when file is empty")
    func createsFromScratch() throws {
        let merged = try HookInstaller.mergeHooks(into: Data("{}".utf8))
        let result = try JSONSerialization.jsonObject(with: merged) as! [String: Any]
        let hooks = result["hooks"] as! [String: Any]
        #expect(hooks["Notification"] != nil)
        #expect(hooks["Stop"] != nil)
    }
}
