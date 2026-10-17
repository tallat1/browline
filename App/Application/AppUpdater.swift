import Foundation
import Observation
import Sparkle

/// Otomatik güncelleme (Sparkle 2). Besleme GitHub'daki `appcast.xml` (Info.plist `SUFeedURL`); arşivler EdDSA ile
/// imzalı (`SUPublicEDKey`, imza `Scripts/release.sh`'te). Otomatik denetim iznini Sparkle ikinci açılışta kendisi
/// sorar; ilk açılışta ağa çıkılmaz. Ad-hoc imzalı sürümler de güncellenir: eski ve yeni sürümün EdDSA anahtarı
/// aynıysa Sparkle kod imzası kimliğinin değişmesine izin verir.
/// Debug derlemesinde başlatılmaz: geliştirme kopyası kendini GitHub'daki sürümle değiştirmesin.
@MainActor
@Observable
final class AppUpdater {
    #if DEBUG
    static let isAvailable = false
    #else
    static let isAvailable = true
    #endif

    @ObservationIgnored private let controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)

    /// Sparkle'ın kendi ayarının (SUEnableAutomaticChecks) yansıması; izin penceresi değiştirebildiği için
    /// ayarlar açılınca `refresh()` ile tazelenir.
    var automaticallyChecks = false {
        didSet {
            guard Self.isAvailable, automaticallyChecks != controller.updater.automaticallyChecksForUpdates else { return }
            controller.updater.automaticallyChecksForUpdates = automaticallyChecks
        }
    }

    /// Uygulama açıldıktan sonra (`AppCoordinator.start()`).
    func start() {
        guard Self.isAvailable else { return }
        controller.startUpdater()
        refresh()
    }

    func refresh() {
        guard Self.isAvailable else { return }
        let current = controller.updater.automaticallyChecksForUpdates
        if automaticallyChecks != current { automaticallyChecks = current }
    }

    var canCheckForUpdates: Bool { Self.isAvailable && controller.updater.canCheckForUpdates }

    func checkForUpdates() {
        guard Self.isAvailable else { return }
        controller.checkForUpdates(nil)
    }
}
