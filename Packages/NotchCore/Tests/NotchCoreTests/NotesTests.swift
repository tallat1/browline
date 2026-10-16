import AppKit
import CoreAudio
import Foundation
import Testing
@testable import Integrations

@MainActor
struct NotesStoreTests {
    @Test func persistsOnFlushAndReloads() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NotesStore(directory: directory)
        #expect(store.text.isEmpty)
        store.text = "süt al\nPR'a bak"
        store.flush()
        #expect(NotesStore(directory: directory).text == "süt al\nPR'a bak")
    }
}
