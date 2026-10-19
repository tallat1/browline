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

/// Raftan dışarı çekilip geri bırakılan öğe yeniden eklenmesin (2026-10-19: sonsuz kez çoğalıyordu).
@MainActor
struct OwnDragTests {
    /// Yalnız `draggingSource` önemli; gerisi protokolün zorunlu üyeleri.
    final class StubDrag: NSObject, NSDraggingInfo {
        let source: Any?
        init(source: Any?) { self.source = source }
        var draggingSource: Any? { source }
        var draggingDestinationWindow: NSWindow? { nil }
        var draggingSourceOperationMask: NSDragOperation { .copy }
        var draggingLocation: NSPoint { .zero }
        var draggedImageLocation: NSPoint { .zero }
        var draggedImage: NSImage? { nil }
        var draggingPasteboard: NSPasteboard { NSPasteboard(name: NSPasteboard.Name("notch-own-drag-test")) }
        var draggingSequenceNumber: Int { 0 }
        var draggingFormation: NSDraggingFormation = .default
        var animatesToDestination = false
        var numberOfValidItemsForDrop = 1
        var springLoadingHighlight: NSSpringLoadingHighlight { .none }
        func slideDraggedImage(to screenPoint: NSPoint) {}
        func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?,
                                    classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
                                    using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
        func resetSpringLoading() {}
    }

    @Test func dragsFromThisAppAreOwn() {
        #expect(FileDrop.isOwnDrag(StubDrag(source: NSView())))
        // Finder ya da ekran görüntüsü küçük resmi: kaynak başka uygulamada, AppKit nil verir.
        #expect(!FileDrop.isOwnDrag(StubDrag(source: nil)))
    }
}
