import AppKit
import CoreAudio
import Foundation
import Testing
@testable import Integrations

struct ShelfActionTests {
    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("notch-raf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func singleItemZipGoesNextToOriginal() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("rapor.txt")
        try "merhaba".write(to: file, atomically: true, encoding: .utf8)
        let destination = ShelfStore.archiveURL(for: [file], downloads: folder, now: .now)
        #expect(destination == folder.appendingPathComponent("rapor.txt.zip"))
        let result = try #require(ShelfStore.runCompression([file], to: destination))
        #expect(FileManager.default.fileExists(atPath: result.path))
        // Var olan adla çakışınca numaralanır.
        #expect(ShelfStore.archiveURL(for: [file], downloads: folder, now: .now).lastPathComponent == "rapor.txt 2.zip")
    }

    @Test func multipleItemsBecomeOneArchive() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = folder.appendingPathComponent("a.txt")
        let second = folder.appendingPathComponent("b.txt")
        try "a".write(to: first, atomically: true, encoding: .utf8)
        try "b".write(to: second, atomically: true, encoding: .utf8)
        let destination = ShelfStore.archiveURL(for: [first, second], downloads: folder, now: Date(timeIntervalSince1970: 0))
        #expect(destination.lastPathComponent.hasPrefix("Arşiv "))
        let result = try #require(ShelfStore.runCompression([first, second], to: destination))
        let listing = Process()
        listing.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo")
        listing.arguments = ["-1", result.path]
        let pipe = Pipe()
        listing.standardOutput = pipe
        try listing.run()
        listing.waitUntilExit()
        let names = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(names.contains("a.txt"))
        #expect(names.contains("b.txt"))
    }
}

struct ShelfConverterTests {
    @Test func optionsDependOnType() {
        let png = ShelfConversion.options(for: URL(fileURLWithPath: "/tmp/a.png"))
        #expect(png.contains(.image(.jpeg)) && png.contains(.image(.heic)) && !png.contains(.image(.png)))
        #expect(png.contains(.resize(maxPixels: 1280)))
        #expect(ShelfConversion.options(for: URL(fileURLWithPath: "/tmp/a.mov")).contains(.audio))
        #expect(ShelfConversion.options(for: URL(fileURLWithPath: "/tmp/a.pdf")).isEmpty)
        #expect(ShelfConversion.options(for: URL(fileURLWithPath: "/tmp/a.JPG")).contains(.image(.png)))
    }

    @Test func outputNames() {
        let source = URL(fileURLWithPath: "/tmp/Ekran Resmi.png")
        #expect(ShelfConversion.image(.jpeg).outputName(for: source) == "Ekran Resmi.jpg")
        #expect(ShelfConversion.resize(maxPixels: 1280).outputName(for: source) == "Ekran Resmi 1280px.png")
        let movie = URL(fileURLWithPath: "/tmp/kayit.mov")
        #expect(ShelfConversion.video(.p720).outputName(for: movie) == "kayit 720p.mp4")
        #expect(ShelfConversion.audio.outputName(for: movie) == "kayit.m4a")
    }

    /// Gerçek sips: 40×30 PNG → JPEG ve 20 px'e küçültme; özgün dosya yerinde kalır.
    @Test func convertsImagesWithSips() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("kare.png")
        let image = NSImage(size: NSSize(width: 40, height: 30), flipped: false) { rect in
            NSColor.systemOrange.setFill()
            rect.fill()
            return true
        }
        let tiff = try #require(image.tiffRepresentation)
        let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        try png.write(to: source)

        let jpeg = try #require(ShelfConverter.run(.image(.jpeg), source: source,
                                                   destination: directory.appendingPathComponent("kare.jpg")))
        #expect(NSImage(contentsOf: jpeg) != nil)
        let small = try #require(ShelfConverter.run(.resize(maxPixels: 20), source: source,
                                                    destination: directory.appendingPathComponent("kare 20px.png")))
        let rep = try #require(NSBitmapImageRep(data: Data(contentsOf: small)))
        #expect(max(rep.pixelsWide, rep.pixelsHigh) == 20)
        #expect(FileManager.default.fileExists(atPath: source.path))
        // Çakışmada numaralı ad.
        #expect(ShelfStore.unique(jpeg).lastPathComponent == "kare 2.jpg")
    }
}
