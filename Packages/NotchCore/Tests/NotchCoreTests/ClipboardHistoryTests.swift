import AppKit
import Testing
@testable import Integrations

/// Ayrı adlı panoyla (genel panoya dokunmaz).
@MainActor
struct ClipboardHistoryTests {
    private func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("notch-test-\(UUID().uuidString)"))
    }

    @Test func capturesTextAndLinksAfterStart() {
        let board = makePasteboard()
        board.clearContents()
        board.setString("önceki", forType: .string)
        let history = ClipboardHistory(pasteboard: board)
        history.check()
        #expect(history.items.isEmpty)  // açılmadan önceki içerik alınmaz

        board.clearContents()
        board.setString("merhaba dünya", forType: .string)
        history.check(source: "com.apple.TextEdit")
        board.clearContents()
        board.setString("https://example.com/a", forType: .string)
        history.check()
        #expect(history.items.count == 2)
        #expect(history.items[0].content == .url(URL(string: "https://example.com/a")!))
        #expect(history.items[1].content == .text("merhaba dünya"))
        #expect(history.items[1].sourceBundleIdentifier == "com.apple.TextEdit")
    }

    @Test func concealedCopiesAreNeverStored() {
        let board = makePasteboard()
        let history = ClipboardHistory(pasteboard: board)
        board.clearContents()
        board.declareTypes([.string, NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")], owner: nil)
        board.setString("gizli-parola", forType: .string)
        history.check()
        #expect(history.items.isEmpty)
    }

    @Test func duplicateMovesToTopAndKeepsPin() {
        let board = makePasteboard()
        let history = ClipboardHistory(pasteboard: board)
        for text in ["a", "b"] {
            board.clearContents()
            board.setString(text, forType: .string)
            history.check()
        }
        history.togglePin(history.items[1].id)  // "a"
        board.clearContents()
        board.setString("a", forType: .string)
        history.check()
        #expect(history.items.map(\.preview) == ["a", "b"])
        #expect(history.items[0].isPinned)
    }

    @Test func copyBackDoesNotCreateNewEntry() {
        let board = makePasteboard()
        let history = ClipboardHistory(pasteboard: board)
        for text in ["bir", "iki"] {
            board.clearContents()
            board.setString(text, forType: .string)
            history.check()
        }
        let first = history.items[1].id  // "bir"
        history.copy(first)
        history.check()
        #expect(board.string(forType: .string) == "bir")
        #expect(history.items.map(\.preview) == ["bir", "iki"])
    }

    @Test func limitAppliesOnlyToUnpinned() {
        let history = ClipboardHistory(pasteboard: makePasteboard())
        history.insert(.text("sabit"), source: nil)
        history.togglePin(history.items[0].id)
        for index in 0..<(ClipboardHistory.maximumItems + 5) { history.insert(.text("\(index)"), source: nil) }
        #expect(history.items.filter { !$0.isPinned }.count == ClipboardHistory.maximumItems)
        #expect(history.items.contains { $0.preview == "sabit" })
        history.clear()
        #expect(history.items.map(\.preview) == ["sabit"])
    }
}
