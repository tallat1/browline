import Darwin
import Foundation
import Testing
@testable import Integrations

struct OrphanedHelpersTests {
    static let app = "/Users/u/Build/Debug/Browline.app/Contents"
    static let adapter = "\(app)/Resources/mediaremote-adapter.pl"
    static let sessions = "\(app)/Resources/media-sessions.pl"
    static let scripts: Set<String> = [adapter, sessions]
    static let user: UInt32 = 501

    static func perl(_ pid: Int32, parent: Int32 = 1, user: UInt32 = user, executable: String? = "/usr/bin/perl",
                     script: String, rest: [String] = ["stream"]) -> ProcessEntry {
        ProcessEntry(pid: pid, parentPID: parent, userID: user, executable: executable,
                     arguments: ["/usr/bin/perl", script] + rest)
    }

    @Test func selectsOnlyOrphansOfThisBundle() {
        let processes = [
            Self.perl(10, script: Self.adapter, rest: ["\(Self.app)/Frameworks/MediaRemoteAdapter.framework", "stream"]),
            Self.perl(11, script: Self.sessions),
            // Çalışan uygulamanın yardımcısı: ebeveyni yaşıyor.
            Self.perl(12, parent: 4000, script: Self.adapter),
            // Başka kopya (Release, /Applications): yol farklı.
            Self.perl(13, script: "/Applications/Browline.app/Contents/Resources/mediaremote-adapter.pl"),
            // Başka kullanıcı.
            Self.perl(14, user: 502, script: Self.adapter),
            // Başka perl.
            Self.perl(15, executable: "/opt/homebrew/bin/perl", script: Self.adapter),
            // Exec yolu okunamadı.
            Self.perl(16, executable: nil, script: Self.adapter),
        ]
        #expect(OrphanedHelpers.select(from: processes, scriptPaths: Self.scripts, userID: Self.user) == [10, 11])
    }

    @Test func pathMatchIsExact() {
        let processes = [
            Self.perl(20, script: Self.adapter + ".bak"),
            Self.perl(21, script: "/x" + Self.adapter),
            Self.perl(22, script: Self.adapter.uppercased()),
            Self.perl(23, script: "mediaremote-adapter.pl"),
            // Betik ilk argüman değil (perl seçeneğinden sonra).
            ProcessEntry(pid: 24, parentPID: 1, userID: Self.user, executable: "/usr/bin/perl",
                         arguments: ["/usr/bin/perl", "-w", Self.adapter]),
            // Betik yalnız argümanlar arasında geçiyor.
            Self.perl(25, script: "/tmp/other.pl", rest: [Self.adapter]),
        ]
        #expect(OrphanedHelpers.select(from: processes, scriptPaths: Self.scripts, userID: Self.user).isEmpty)
    }

    @Test func neverSelectsLaunchdOrMissingArguments() {
        let processes = [
            Self.perl(1, script: Self.adapter),
            Self.perl(0, script: Self.adapter),
            ProcessEntry(pid: 30, parentPID: 1, userID: Self.user, executable: "/usr/bin/perl", arguments: []),
            ProcessEntry(pid: 31, parentPID: 1, userID: Self.user, executable: "/usr/bin/perl", arguments: ["/usr/bin/perl"]),
        ]
        #expect(OrphanedHelpers.select(from: processes, scriptPaths: Self.scripts, userID: Self.user).isEmpty)
        #expect(OrphanedHelpers.select(from: [Self.perl(10, script: Self.adapter)], scriptPaths: [], userID: Self.user).isEmpty)
    }

    @Test func scriptPathsComeFromBundleResources() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("orphan-\(UUID().uuidString).app")
        defer { try? FileManager.default.removeItem(at: root) }
        let resources = root.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try Data("<plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>test.orphan</string></dict></plist>".utf8)
            .write(to: root.appendingPathComponent("Contents/Info.plist"))
        try Data().write(to: resources.appendingPathComponent("mediaremote-adapter.pl"))
        let bundle = try #require(Bundle(url: root))
        // Yalnız var olan betik; media-sessions.pl yok.
        let paths = OrphanedHelpers.scriptPaths(in: bundle)
        #expect(paths.count == 1)
        #expect(paths.first?.hasSuffix("/Contents/Resources/mediaremote-adapter.pl") == true)
    }

    @Test func parsesProcArgsLayout() throws {
        var bytes = withUnsafeBytes(of: Int32(3).littleEndian) { Array($0) }
        bytes += Array("/usr/bin/perl".utf8) + [0, 0, 0, 0]
        for argument in ["/usr/bin/perl", Self.adapter, "stream"] { bytes += Array(argument.utf8) + [0] }
        bytes += Array("PATH=/usr/bin".utf8) + [0]
        let parsed = try #require(ProcessTable.parseProcArgs(bytes))
        #expect(parsed.executable == "/usr/bin/perl")
        #expect(parsed.arguments == ["/usr/bin/perl", Self.adapter, "stream"])

        #expect(ProcessTable.parseProcArgs([]) == nil)
        #expect(ProcessTable.parseProcArgs([2, 0, 0, 0] + Array("/bin/x".utf8)) == nil)  // NUL yok
        #expect(ProcessTable.parseProcArgs([2, 0, 0, 0] + Array("/bin/x".utf8) + [0, 0] + Array("a".utf8) + [0]) == nil)  // argc eksik
    }

    /// Sistem katmanı gerçek süreç tablosunda: test sürecinin kendisi doğru okunuyor.
    @Test func readsOwnProcessFromTable() throws {
        let own = getpid()
        let entries = ProcessTable.entries { $0.pid == own }
        let entry = try #require(entries.first)
        #expect(entries.count == 1)
        #expect(entry.parentPID == getppid())
        #expect(entry.userID == getuid())
        #expect(entry.arguments.first.map { !$0.isEmpty } == true)
        #expect(entry.executable != nil)
    }
}
