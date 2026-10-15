import Foundation
import Testing
@testable import Integrations

struct DownloadNamingTests {
    @Test(arguments: [
        ("rapor.pdf.crdownload", "rapor.pdf"),
        ("Unconfirmed 123.crdownload", "Unconfirmed 123"),
        ("arşiv.zip.download", "arşiv.zip"),
        ("video.mp4.part", "video.mp4"),
    ])
    func partialNames(_ partial: String, _ final: String) {
        #expect(DownloadNaming.finalName(forPartial: partial) == final)
    }

    @Test func ignoresOrdinaryAndHiddenFiles() {
        #expect(DownloadNaming.finalName(forPartial: "rapor.pdf") == nil)
        #expect(DownloadNaming.finalName(forPartial: ".DS_Store") == nil)
        #expect(DownloadNaming.finalName(forPartial: ".part") == nil)
    }
}

@MainActor
struct DownloadsMonitorTests {
    @Test func detectsActiveAndFinishedDownloads() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let monitor = DownloadsMonitor(directory: directory)
        var finished: [String] = []
        monitor.onFinished = { finished.append($0) }

        let partial = directory.appendingPathComponent("veri.csv.crdownload")
        try Data(count: 2048).write(to: partial)
        monitor.scan()
        #expect(monitor.active.map(\.name) == ["veri.csv"])
        #expect(monitor.active.first?.bytes == 2048)

        try FileManager.default.moveItem(at: partial, to: directory.appendingPathComponent("veri.csv"))
        monitor.scan()
        #expect(monitor.active.isEmpty)
        #expect(finished == ["veri.csv"])
    }
}
