import Testing
import Foundation
@testable import CodeSquad

@Suite("HookPayload parsing")
struct HookPayloadTests {
    @Test("Parses valid notify payload")
    func validNotify() throws {
        let json = """
        {
            "session_id": "abc123",
            "cwd": "/Users/dev/Projects/vscode-squad",
            "hook_event_name": "Notification",
            "notification_type": "permission_prompt"
        }
        """.data(using: .utf8)!

        let payload = try JSONDecoder().decode(HookPayload.self, from: json)
        #expect(payload.sessionId == "abc123")
        #expect(payload.cwd == "/Users/dev/Projects/vscode-squad")
        #expect(payload.hookEventName == "Notification")
    }

    @Test("Parses valid stop payload")
    func validStop() throws {
        let json = """
        {
            "session_id": "abc123",
            "cwd": "/Users/dev/Projects/vscode-squad",
            "hook_event_name": "Stop"
        }
        """.data(using: .utf8)!

        let payload = try JSONDecoder().decode(HookPayload.self, from: json)
        #expect(payload.hookEventName == "Stop")
    }

    @Test("Ignores unknown fields without failing")
    func unknownFields() throws {
        let json = """
        {
            "session_id": "abc123",
            "cwd": "/some/path",
            "hook_event_name": "Notification",
            "transcript_path": "/some/transcript.jsonl",
            "permission_mode": "default",
            "future_field": "should be ignored"
        }
        """.data(using: .utf8)!

        let payload = try JSONDecoder().decode(HookPayload.self, from: json)
        #expect(payload.cwd == "/some/path")
    }

    @Test("Fails on missing cwd")
    func missingCwd() {
        let json = """
        {
            "session_id": "abc123",
            "hook_event_name": "Notification"
        }
        """.data(using: .utf8)!

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(HookPayload.self, from: json)
        }
    }
}
