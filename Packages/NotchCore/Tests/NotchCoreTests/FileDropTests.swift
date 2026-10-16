import AppKit
import Foundation
import Testing
@testable import Integrations
@testable import NotchShell

/// Ekran görüntüsü küçük resmi gibi dosya sözleri ve yalnız görsel verisi notch'a bırakılabilmeli.
@MainActor
struct FileDropTests {
    private func pasteboard() -> NSPasteboard {
        let board = NSPasteboard(name: NSPasteboard.Name("notch-test-\(UUID().uuidString)"))
        board.clearContents()
        return board
    }

    @Test func detectsFilePromisesAndImagesButNotText() throws {
        let promise = pasteboard()
        let promiseType = try #require(FileDrop.promiseTypes.first)
        promise.declareTypes([promiseType], owner: nil)
        promise.setString("public.png", forType: promiseType)
        #expect(FileDrop.carriesFiles(promise))

        let text = pasteboard()
        text.setString("merhaba", forType: .string)
        #expect(!FileDrop.carriesFiles(text))

        let file = pasteboard()
        file.writeObjects([URL(fileURLWithPath: "/tmp") as NSURL])
        #expect(FileDrop.carriesFiles(file))
    }

    @Test func imageDataIsWrittenAsPNG() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
            NSColor.systemBlue.setFill()
            rect.fill()
            return true
        }
        let board = pasteboard()
        board.writeObjects([image])
        #expect(FileDrop.carriesFiles(board))
        let url = try #require(FileDrop.writeImage(from: board, to: directory))
        #expect(url.pathExtension == "png")
        #expect(NSImage(contentsOf: url) != nil)
    }

    @Test func temporaryItemsAreCopied() throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("notch-gecici-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        #expect(FileDrop.isTemporary(source))
        #expect(!FileDrop.isTemporary(URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop/a.png")))
        let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: target) }
        let copied = try #require(FileDrop.copy(source, to: target))
        #expect(FileManager.default.fileExists(atPath: copied.path))
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test func promiseDestinationExists() {
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: ShelfStore.promiseDestination().path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }
}
