import AppKit
import Integrations
import NotchShell
import SwiftUI

/// İlk açılış: notch'u tanıt → nasıl kullanıyorsunuz (çoklu profil) → yalnız gereken izinler. Rakip
/// araştırması (2026-10-16): Atoll profil seçtiriyor ama sonuncusu öncekini eziyor; burada profiller
/// birleşerek açar. İzinler başta en fazla iki üç tane, her biri nedeniyle ve "Şimdi değil"le.
enum OnboardingProfile: String, CaseIterable, Identifiable, Sendable {
    case media, meetings, developer, files

    var id: String { rawValue }

    var title: String {
        switch self {
        case .media: String(localized: "Müzik ve medya")
        case .meetings: String(localized: "Toplantılar")
        case .developer: String(localized: "Geliştirici")
        case .files: String(localized: "Dosyalar ve pano")
        }
    }

    var detail: String {
        switch self {
        case .media: String(localized: "Çalan şarkı, şarkı ve ses çıkışı bildirimleri, Bluetooth pil")
        case .meetings: String(localized: "Takvim, anımsatıcılar, mikrofonu sessize alma, kamera ve ekran kaydı göstergesi")
        case .developer: String(localized: "Terminal, CI durumu, Claude limitleri ve izin istemleri, sistem durumu")
        case .files: String(localized: "Dosya rafı, AirDrop, dönüştürme ve pano geçmişi")
        }
    }

    var symbol: String {
        switch self {
        case .media: "music.note"
        case .meetings: "video.fill"
        case .developer: "chevron.left.forwardslash.chevron.right"
        case .files: "tray.full.fill"
        }
    }

    var tint: Color {
        switch self {
        case .media: .pink
        case .meetings: .red
        case .developer: .indigo
        case .files: .teal
        }
    }

    /// Profilin açtığı özellikler (AppSettings ana iş parçacığında).
    @MainActor var features: [ReferenceWritableKeyPath<AppSettings, Bool>] {
        switch self {
        case .media:
            [\.nowPlayingEnabled, \.trackPeekEnabled, \.audioOutputAlertEnabled, \.bluetoothEnabled, \.animatedEqualizer]
        case .meetings:
            [\.calendarEnabled, \.remindersEnabled, \.meetingControlsEnabled, \.privacyIndicatorEnabled,
             \.screenRecordingIndicatorEnabled]
        case .developer:
            [\.terminalEnabled, \.ciEnabled, \.claudeUsageEnabled, \.activityAPIEnabled, \.questionsEnabled, \.choiceQuestionsEnabled,
             \.decisionCardsEnabled, \.systemStatsEnabled]
        case .files:
            [\.shelfEnabled, \.clipboardEnabled]
        }
    }

    /// Profilden bağımsız hep açık temel parçalar.
    @MainActor static var basics: [ReferenceWritableKeyPath<AppSettings, Bool>] {
        [\.batteryEnabled, \.keepAwakeEnabled, \.notesEnabled, \.timerEnabled]
    }

    /// Seçilen profillerin birleşimi açılır, hiçbir seçili profilde olmayan profil özellikleri kapanır.
    /// Profillere girmeyen ayarlara (hava, ayna, kilit ekranı…) dokunulmaz.
    @MainActor
    static func apply(_ selected: Set<OnboardingProfile>, to settings: AppSettings) {
        let enabled = Set(selected.flatMap(\.features) + basics)
        let all = Set(allCases.flatMap(\.features) + basics)
        for keyPath in all {
            let value = enabled.contains(keyPath)
            if settings[keyPath: keyPath] != value { settings[keyPath: keyPath] = value }
        }
    }
}

@MainActor
@Observable
final class OnboardingModel {
    var step = 0
    var profiles: Set<OnboardingProfile> = [.media, .files]
    static let stepCount = 3
}
