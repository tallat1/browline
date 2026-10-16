import ActivityAPI
import ActivityEngine
import AppKit
import Integrations
import NotchShell
import Observation
import SwiftUI

/// Açık notch'un beş ana bölümü (2026-10-16, kullanıcı seçimi: "5 ana bölüm"). Bantta yalnız bunlar;
/// ••• şeridi yok. Bir bölümde birden çok sayfa varsa içeriğin üstünde küçük bir seçici çıkar, her
/// bölüm son açılan sayfasını hatırlar. Özellik eklendikçe bant büyümez: yeni sayfa bir bölüme girer.
enum NotchSection: String, CaseIterable, Identifiable, Sendable {
    case now
    case shelf
    case calendar
    case tools
    case status

    var id: String { rawValue }

    /// Seçicide görünen sayfalar, sırasıyla. Etkinlikler Şimdi'nin ayrıntı sayfası: seçicide yok,
    /// Şimdi'deki etkinlik kartından açılır.
    var pages: [NotchPage] {
        switch self {
        case .now: [.now]
        case .shelf: [.shelf, .clipboard]
        case .calendar: [.calendar]
        case .tools: [.notes, .timer, .terminal, .mirror]
        case .status: [.system, .claude, .ci]
        }
    }

    var symbol: String {
        switch self {
        case .now: "house"
        case .shelf: "tray.full"
        case .calendar: "calendar"
        case .tools: "wrench.and.screwdriver"
        case .status: "gauge.with.dots.needle.33percent"
        }
    }

    var title: String {
        switch self {
        case .now: String(localized: "Şimdi")
        case .shelf: String(localized: "Raf")
        case .calendar: String(localized: "Takvim")
        case .tools: String(localized: "Araçlar")
        case .status: String(localized: "Durum")
        }
    }
}

/// Açık notch'un sayfaları; her biri bir bölümde (`section`).
enum NotchPage: String, CaseIterable, Identifiable, Sendable {
    case now
    case calendar
    case shelf
    case activities
    case notes
    case timer
    case system
    case mirror
    case claude
    case terminal
    case clipboard
    case ci

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .now: "house"
        case .calendar: "calendar"
        case .shelf: "tray.full"
        case .activities: "square.stack.3d.up"
        case .notes: "note.text"
        case .timer: "timer"
        case .system: "cpu"
        case .mirror: "person.crop.square"
        case .claude: "sparkles"
        case .terminal: "terminal"
        case .clipboard: "doc.on.clipboard"
        case .ci: "hammer"
        }
    }

    var title: String {
        switch self {
        case .now: String(localized: "Şimdi")
        case .calendar: String(localized: "Takvim")
        case .shelf: String(localized: "Raf")
        case .activities: String(localized: "Etkinlikler")
        case .notes: String(localized: "Not")
        case .timer: String(localized: "Zamanlayıcı")
        case .system: String(localized: "Sistem")
        case .mirror: String(localized: "Ayna")
        case .claude: "Claude"
        case .terminal: String(localized: "Terminal")
        case .clipboard: String(localized: "Pano")
        case .ci: "CI"
        }
    }

    var section: NotchSection {
        switch self {
        case .now, .activities: .now
        case .shelf, .clipboard: .shelf
        case .calendar: .calendar
        case .notes, .timer, .terminal, .mirror: .tools
        case .system, .claude, .ci: .status
        }
    }

    /// Seçicide değil, bir karttan açılan ayrıntı sayfası (geri düğmesiyle).
    var isDetailPage: Bool { !section.pages.contains(self) }
}

/// Açık notch'taki seçili sekme; tüm ekranlarda ortak.
@MainActor
@Observable
final class NotchUIState {
    var selectedPage: NotchPage = .now {
        didSet { if !selectedPage.isDetailPage { lastPage[selectedPage.section] = selectedPage } }
    }
    /// Bölüm başına son açılan sayfa: bölüme dönünce oradan devam edilir.
    var lastPage: [NotchSection: NotchPage] = [:]
    var activityAPIStatus = String(localized: "Kapalı")
    #if DEBUG
    /// README görüntüleri: Şimdi'de gerçek toplantı, mikrofon, Claude ve dış etkinlik kartları gizlenir;
    /// yalnız `demo.` ile başlayan etkinlikler görünür. Yalnız debug derlemesinde.
    var isDemoMode = false
    #endif
    /// Son tamamlanan indirmenin adı (kısa bildirimde gösterilir).
    var lastFinishedDownload = ""
    /// Pomodoro açıksa şu anki evre; düz zamanlayıcıda nil.
    var pomodoroPhase: Pomodoro.Phase?
    /// Son Bluetooth olayı (kısa bildirimde gösterilir).
    var bluetoothEvent: BluetoothEvent?
    /// Mikrofon kısayolu kaydedilemedi (birleşim başka uygulamada kayıtlı).
    var micShortcutUnavailable = false
    /// Son biten CI çalışması (kısa bildirimde gösterilir).
    var lastFinishedRun: CIMonitor.Run?
    /// Ayarlar penceresinde açık sayfa ve vurgulanacak ayar (arama ya da notch'tan doğrudan gelince).
    var settingsPage: SettingsPage = .general
    var settingsHighlight: String?
}
