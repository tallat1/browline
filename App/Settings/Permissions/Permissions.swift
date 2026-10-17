import AVFoundation
import AppKit
import ApplicationServices
import Integrations
import Observation
import SwiftUI

/// Uygulamanın isteyebileceği izinler. Adlar Sistem Ayarları'nın kendi metninden okunur: macOS 27'de
/// Erişilebilirlik bölmesinin adı "Aygıt Denetimi ve Veri Erişimi" oldu (kaynak: SecurityPrivacyExtension
/// Localizable.loctable, `ACCESSIBILITY`; boring.notch #1561). Koda gömülü ad sürüm değişince eskir.
enum PermissionKind: String, CaseIterable, Identifiable, Sendable {
    case calendar, reminders, camera, accessibility, systemAudio, automation, downloads

    var id: String { rawValue }

    /// Sistem Ayarları › Gizlilik ve Güvenlik'teki bölmenin adı (sistemin dilinde değil, uygulamanın).
    var systemName: String {
        guard let key = systemKey, let bundle = Self.systemStrings else { return fallbackName }
        let name: String
        if #available(macOS 15.4, *) {
            name = bundle.localizedString(forKey: key, value: nil, table: "Localizable", localizations: [Self.appLanguage])
        } else {
            name = bundle.localizedString(forKey: key, value: nil, table: "Localizable")
        }
        return name == key || name.isEmpty ? fallbackName : name
    }

    /// Sistemden okunamazsa: sürüme göre bilinen ad.
    var fallbackName: String {
        switch self {
        case .calendar: String(localized: "Takvimler")
        case .reminders: String(localized: "Anımsatıcılar")
        case .camera: String(localized: "Kamera")
        case .accessibility:
            ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0))
                ? String(localized: "Aygıt Denetimi ve Veri Erişimi") : String(localized: "Erişilebilirlik")
        case .systemAudio: String(localized: "Ekran ve Sistem Sesi Kaydı")
        case .automation: String(localized: "Otomasyon")
        case .downloads: String(localized: "Dosyalar ve Klasörler")
        }
    }

    /// Ne için gerektiği, özelliğin diliyle.
    var purpose: String {
        switch self {
        case .calendar: String(localized: "Yaklaşan toplantı ve Katıl düğmesi")
        case .reminders: String(localized: "Bugünün anımsatıcıları Takvim'de")
        case .camera: String(localized: "Ayna sayfası; görüntü kaydedilmez")
        case .accessibility: String(localized: "Ses ve parlaklık tuşlarını notch'a almak ve karar kartında seçtiğiniz Claude düğmesine basmak")
        case .systemAudio: String(localized: "Müziğe tepki veren çubuklar; ses kaydedilmez")
        case .automation: String(localized: "MediaRemote çalışmazsa Spotify ve Music denetimi")
        case .downloads: String(localized: "Biten indirmeleri göstermek (İndirilenler klasörü)")
        }
    }

    var symbol: String {
        switch self {
        case .calendar: "calendar"
        case .reminders: "checklist"
        case .camera: "camera.fill"
        case .accessibility: "hand.point.up.left.fill"
        case .systemAudio: "waveform"
        case .automation: "gearshape.2.fill"
        case .downloads: "folder.fill"
        }
    }

    var tint: Color {
        switch self {
        case .calendar: .red
        case .reminders: .orange
        case .camera: .green
        case .accessibility: .blue
        case .systemAudio: .pink
        case .automation: .gray
        case .downloads: .teal
        }
    }

    /// Gizlilik ve Güvenlik'te doğrudan açılacak bölme.
    var paneURL: URL? {
        let anchor = switch self {
        case .calendar: "Privacy_Calendars"
        case .reminders: "Privacy_Reminders"
        case .camera: "Privacy_Camera"
        case .accessibility: "Privacy_Accessibility"
        case .systemAudio: "Privacy_ScreenCapture"
        case .automation: "Privacy_Automation"
        case .downloads: "Privacy_FilesAndFolders"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
    }

    private var systemKey: String? {
        switch self {
        case .calendar: "CALENDARS"
        case .reminders: "REMINDERS"
        case .camera: "CAMERA"
        case .accessibility: "ACCESSIBILITY"
        case .systemAudio: "SCREENANDAUDIOCAPTURE"
        case .automation: "AUTOMATION"
        case .downloads: "FILE_ACCESS_COMBINED"
        }
    }

    private static let systemStrings = Bundle(path: "/System/Library/ExtensionKit/Extensions/SecurityPrivacyExtension.appex")
    private static var appLanguage: Locale.Language {
        Locale.Language(identifier: Bundle.main.preferredLocalizations.first ?? "en")
    }
}

enum PermissionStatus: Equatable, Sendable {
    case granted
    case denied
    case notDetermined
    /// İzin durumu okunamıyor (sistem sesi kaydı: public API yok; Otomasyon: hedef uygulama kapalı).
    case unknown

    var title: String {
        switch self {
        case .granted: String(localized: "Verildi")
        case .denied: String(localized: "Verilmedi")
        case .notDetermined: String(localized: "İstenmedi")
        case .unknown: String(localized: "Bilinmiyor")
        }
    }
}

/// İzin durumları. Zamanlayıcıyla yoklanmaz: uygulama etkinleşince (kullanıcı Sistem Ayarları'ndan
/// döndüğünde), ayarlar açılınca ve bir izin istendikten sonra yenilenir.
@MainActor
@Observable
final class PermissionCenter {
    private(set) var statuses: [PermissionKind: PermissionStatus] = [:]
    @ObservationIgnored private weak var coordinator: AppCoordinator?
    @ObservationIgnored private var observer: NSObjectProtocol?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil,
                                                          queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    func status(_ kind: PermissionKind) -> PermissionStatus { statuses[kind] ?? .unknown }

    /// Bu iznin şu an açık bir özellik için gerekip gerekmediği.
    func isNeeded(_ kind: PermissionKind) -> Bool {
        guard let coordinator else { return false }
        let settings = coordinator.settings
        return switch kind {
        case .calendar: settings.calendarEnabled
        case .reminders: settings.calendarEnabled && settings.remindersEnabled
        case .camera: settings.mirrorEnabled
        case .accessibility: settings.hudMode == .replace || (settings.activityAPIEnabled && settings.decisionCardsEnabled)
        case .systemAudio: settings.animatedEqualizer && settings.reactiveEqualizer
        case .automation: settings.nowPlayingEnabled
        case .downloads: settings.downloadsEnabled
        }
    }

    func refresh() {
        guard let coordinator else { return }
        var fresh: [PermissionKind: PermissionStatus] = [:]
        fresh[.calendar] = Self.map(coordinator.calendar.access)
        fresh[.reminders] = Self.map(coordinator.reminders.access)
        fresh[.camera] = switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .granted
        case .denied, .restricted: .denied
        case .notDetermined: .notDetermined
        @unknown default: .unknown
        }
        fresh[.accessibility] = AXIsProcessTrusted() ? .granted : .notDetermined
        fresh[.systemAudio] = coordinator.spectrum.levels.everHadSignal ? .granted : .unknown
        fresh[.automation] = Self.automationStatus()
        fresh[.downloads] = coordinator.settings.downloadsEnabled ? (coordinator.downloads.isRunning ? .granted : .denied) : .unknown
        if fresh != statuses { statuses = fresh }
    }

    /// Mümkünse sistemin izin penceresini açar, değilse doğru gizlilik bölmesini.
    func request(_ kind: PermissionKind) {
        guard let coordinator else { return }
        switch (kind, status(kind)) {
        case (.calendar, .notDetermined):
            Task { await coordinator.calendar.requestAccess(); refresh() }
        case (.reminders, .notDetermined):
            Task { await coordinator.reminders.requestAccess(); refresh() }
        case (.camera, .notDetermined):
            Task {
                _ = await AVCaptureDevice.requestAccess(for: .video)
                refresh()
            }
        case (.accessibility, .notDetermined):
            Self.openAccessibilitySetup()
        default:
            openPane(kind)
        }
    }

    func openPane(_ kind: PermissionKind) {
        if let url = kind.paneURL { NSWorkspace.shared.open(url) }
    }

    /// Erişilebilirlik: bölme açılır ve Browline Finder'da seçili gösterilir; kullanıcı uygulamayı listeye sürükleyip
    /// anahtarını açar. ⚠️ macOS 27'de (2026-10-17) uygulama listeye kendiliğinden EKLENMİYOR: ne sistemin istemi
    /// (`AXIsProcessTrustedWithOptions`) ne izinsiz bir AX çağrısı ekledi, kullanıcı açacak satır bulamadı.
    static func openAccessibilitySetup() {
        if let url = PermissionKind.accessibility.paneURL { NSWorkspace.shared.open(url) }
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    private static func map(_ access: CalendarMonitor.Access) -> PermissionStatus {
        switch access {
        case .granted: .granted
        case .denied: .denied
        case .notDetermined: .notDetermined
        }
    }

    private static func map(_ access: RemindersMonitor.Access) -> PermissionStatus {
        switch access {
        case .granted: .granted
        case .denied: .denied
        case .notDetermined: .notDetermined
        }
    }

    /// Spotify ya da Music için Otomasyon izni; pencere açmadan sorulur. Hedef kapalıysa okunamaz.
    private static func automationStatus() -> PermissionStatus {
        var results: [PermissionStatus] = []
        for bundleID in ["com.spotify.client", "com.apple.Music"] {
            guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else { continue }
            var target = AEAddressDesc()
            let data = Array(bundleID.utf8)
            guard AECreateDesc(DescType(typeApplicationBundleID), data, data.count, &target) == noErr else { continue }
            defer { AEDisposeDesc(&target) }
            let status = AEDeterminePermissionToAutomateTarget(&target, AEEventClass(typeWildCard), AEEventID(typeWildCard), false)
            switch status {
            case noErr: results.append(.granted)
            case OSStatus(errAEEventNotPermitted): results.append(.denied)
            case OSStatus(errAEEventWouldRequireUserConsent): results.append(.notDetermined)
            default: break
            }
        }
        if results.contains(.granted) { return .granted }
        if results.contains(.denied) { return .denied }
        if results.contains(.notDetermined) { return .notDetermined }
        return .unknown
    }
}
