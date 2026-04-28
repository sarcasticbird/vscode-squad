import Testing
import Foundation
@testable import Conductor

@Suite("StatePersistence")
struct StatePersistenceTests {
    @Test("Round-trips persisted state")
    func roundTrip() throws {
        let original = PersistedState(panelX: 100.5, panelY: 200.0, hooksInstalled: true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PersistedState.self, from: data)
        #expect(decoded.panelX == 100.5)
        #expect(decoded.panelY == 200.0)
        #expect(decoded.hooksInstalled == true)
    }

    @Test("Provides defaults when file missing")
    func defaultsOnMissing() {
        let state = StatePersistence.load(from: "/tmp/nonexistent-conductor-state.json")
        #expect(state.panelX == nil)
        #expect(state.panelY == nil)
        #expect(state.hooksInstalled == false)
    }

    @Test("Writes and reads back from disk")
    func writeAndRead() throws {
        let path = "/tmp/conductor-test-state-\(UUID().uuidString).json"
        let original = PersistedState(panelX: 50, panelY: 300, hooksInstalled: true)
        try StatePersistence.save(original, to: path)
        let loaded = StatePersistence.load(from: path)
        #expect(loaded.panelX == 50)
        #expect(loaded.panelY == 300)
        #expect(loaded.hooksInstalled == true)
        try? FileManager.default.removeItem(atPath: path)
    }
}
