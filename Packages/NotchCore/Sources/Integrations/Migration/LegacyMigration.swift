import Foundation

/// Çalışma adından ürün adına geçiş (2026-10-16): paket kimliği `com.talatozcoban.notchmvp` →
/// `com.talatozcoban.browline`. Ayarlar ve Application Support klasörü (raf, not, Claude kullanımı) ilk
/// açılışta bir kez taşınır. TCC izinleri kimliğe bağlı olduğu için taşınamaz; kullanıcı bir kez yeniden verir.
public enum LegacyMigration {
    public static let legacyIdentifier = "com.talatozcoban.notchmvp"
    static let doneKey = "migratedFromLegacyIdentifier"

    public struct Outcome: Equatable, Sendable {
        /// Yeni alana yazılan ayar sayısı.
        public var copiedSettings = 0
        public var movedDataFolder = false
    }

    /// Yeni kimlikte zaten yazılmış ayar eskisiyle ezilmez; yeni klasör varsa eskisi taşınmaz.
    /// Ayarlar okunmadan önce (uygulama temsilcisi kurulmadan) çağrılmalı.
    @discardableResult
    public static func run(
        identifier: String,
        legacyIdentifier: String = legacyIdentifier,
        defaults: UserDefaults,
        supportDirectory: URL,
        fileManager: FileManager = .default
    ) -> Outcome {
        var outcome = Outcome()
        guard identifier != legacyIdentifier, !defaults.bool(forKey: doneKey) else { return outcome }

        let current = defaults.persistentDomain(forName: identifier) ?? [:]
        for (key, value) in defaults.persistentDomain(forName: legacyIdentifier) ?? [:] where current[key] == nil {
            defaults.set(value, forKey: key)
            outcome.copiedSettings += 1
        }

        let legacyFolder = supportDirectory.appendingPathComponent(legacyIdentifier, isDirectory: true)
        let folder = supportDirectory.appendingPathComponent(identifier, isDirectory: true)
        if fileManager.fileExists(atPath: legacyFolder.path), !fileManager.fileExists(atPath: folder.path) {
            do {
                try fileManager.moveItem(at: legacyFolder, to: folder)
                outcome.movedDataFolder = true
            } catch {
                Log.integrations.error("Eski veri klasörü taşınamadı: \(error.localizedDescription, privacy: .public)")
            }
        }

        defaults.set(true, forKey: doneKey)
        Log.integrations.notice("Kimlik geçişi: \(outcome.copiedSettings) ayar, klasör \(outcome.movedDataFolder)")
        return outcome
    }
}
