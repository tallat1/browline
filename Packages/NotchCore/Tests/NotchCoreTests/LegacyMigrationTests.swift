import Foundation
import Testing
@testable import Integrations

/// Gerçek tercih dosyası yazılır (~/Library/Preferences/notchcore-test-*.plist); her test kendi alanını siler.
@Suite(.serialized)
struct LegacyMigrationTests {
    private func makeDomains() -> (identifier: String, legacy: String, defaults: UserDefaults, support: URL) {
        let tag = UUID().uuidString
        let identifier = "notchcore-test-new-\(tag)"
        let support = FileManager.default.temporaryDirectory.appendingPathComponent("migration-\(tag)", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return (identifier, "notchcore-test-old-\(tag)", UserDefaults(suiteName: identifier)!, support)
    }

    private func cleanUp(_ domains: (identifier: String, legacy: String, defaults: UserDefaults, support: URL)) {
        domains.defaults.removePersistentDomain(forName: domains.identifier)
        domains.defaults.removePersistentDomain(forName: domains.legacy)
        try? FileManager.default.removeItem(at: domains.support)
        // removePersistentDomain dosyayı bırakıyor; tercih klasöründe deneme dosyası kalmasın.
        let preferences = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences")
        for name in [domains.identifier, domains.legacy] {
            try? FileManager.default.removeItem(at: preferences.appendingPathComponent("\(name).plist"))
        }
    }

    @Test func copiesSettingsAndMovesDataOnce() throws {
        let d = makeDomains()
        defer { cleanUp(d) }
        d.defaults.setPersistentDomain(["hasCompletedOnboarding": true, "shelfEnabled": false], forName: d.legacy)
        d.defaults.set(true, forKey: "shelfEnabled")  // yeni kimlikte yazılmış değer korunmalı
        let legacyFolder = d.support.appendingPathComponent(d.legacy, isDirectory: true)
        try FileManager.default.createDirectory(at: legacyFolder, withIntermediateDirectories: true)
        try "not".write(to: legacyFolder.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

        let outcome = LegacyMigration.run(identifier: d.identifier, legacyIdentifier: d.legacy,
                                          defaults: d.defaults, supportDirectory: d.support)

        #expect(outcome == .init(copiedSettings: 1, movedDataFolder: true))
        #expect(d.defaults.bool(forKey: "hasCompletedOnboarding"))
        #expect(d.defaults.bool(forKey: "shelfEnabled"))
        let moved = d.support.appendingPathComponent(d.identifier).appendingPathComponent("notes.txt")
        #expect(try String(contentsOf: moved, encoding: .utf8) == "not")
        #expect(!FileManager.default.fileExists(atPath: legacyFolder.path))

        // İkinci açılışta hiçbir şey yapılmaz.
        d.defaults.setPersistentDomain(["weatherEnabled": true], forName: d.legacy)
        #expect(LegacyMigration.run(identifier: d.identifier, legacyIdentifier: d.legacy,
                                    defaults: d.defaults, supportDirectory: d.support) == .init())
        #expect(d.defaults.object(forKey: "weatherEnabled") == nil)
    }

    @Test func freshInstallOnlyMarksDone() {
        let d = makeDomains()
        defer { cleanUp(d) }
        #expect(LegacyMigration.run(identifier: d.identifier, legacyIdentifier: d.legacy,
                                    defaults: d.defaults, supportDirectory: d.support) == .init())
        #expect(d.defaults.bool(forKey: "migratedFromLegacyIdentifier"))
    }

    @Test func keepsExistingNewFolder() throws {
        let d = makeDomains()
        defer { cleanUp(d) }
        for name in [d.legacy, d.identifier] {
            try FileManager.default.createDirectory(at: d.support.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        let outcome = LegacyMigration.run(identifier: d.identifier, legacyIdentifier: d.legacy,
                                          defaults: d.defaults, supportDirectory: d.support)
        #expect(!outcome.movedDataFolder)
        #expect(FileManager.default.fileExists(atPath: d.support.appendingPathComponent(d.legacy).path))
    }
}
