import ActivityAPI
import ActivityEngine
import AppKit
import Integrations
import NotchShell
import Observation
import SwiftUI

/// Açık notch'ta bölüm ve sayfa seçimi; menüden ve ayarlardan açma.
extension AppCoordinator {
    /// Ayarları belirli sayfada ve isteğe bağlı olarak bir ayar vurgulanmış açar.
    func showSettings(_ page: SettingsPage, highlight: String? = nil) {
        ui.settingsPage = page
        ui.settingsHighlight = highlight
        openSettings?()
    }

    /// Açılabilen sayfalar: modülü açık ve ayarlardan gizlenmemiş. Şimdi hep var.
    var availablePages: [NotchPage] {
        NotchPage.allCases.filter { $0 == .now || (isModuleEnabled(for: $0) && !settings.hiddenPages.contains($0)) }
    }

    /// Bölümün seçicideki açık sayfaları.
    func pages(in section: NotchSection) -> [NotchPage] {
        let available = availablePages
        return section.pages.filter(available.contains)
    }

    /// Bantta görünen bölümler: en az bir sayfası açık olanlar.
    var availableSections: [NotchSection] {
        NotchSection.allCases.filter { !pages(in: $0).isEmpty }
    }

    /// Bölüm simgesine basınca: başka bölümden geliniyorsa son sayfasına, aynı bölümdeyse (ayrıntı
    /// sayfasından dönüş) ilk sayfasına.
    func select(_ section: NotchSection) {
        let pages = pages(in: section)
        guard let first = pages.first else { return }
        if ui.selectedPage.section == section {
            if ui.selectedPage.isDetailPage { ui.selectedPage = first }
            return
        }
        if let last = ui.lastPage[section], pages.contains(last) {
            ui.selectedPage = last
        } else {
            ui.selectedPage = first
        }
    }

    func isModuleEnabled(for page: NotchPage) -> Bool {
        switch page {
        // Şimdi her zaman var: müzik kapalıysa da toplantı, etkinlik ve zamanlayıcı orada.
        case .now: true
        case .calendar: settings.calendarEnabled
        case .shelf: settings.shelfEnabled
        case .activities: settings.activityAPIEnabled
        case .notes: settings.notesEnabled
        case .timer: settings.timerEnabled
        case .system: settings.systemStatsEnabled
        case .mirror: settings.mirrorEnabled
        case .claude: settings.claudeUsageEnabled
        case .terminal: settings.terminalEnabled
        case .clipboard: settings.clipboardEnabled
        case .ci: settings.ciEnabled
        }
    }
    /// Menüden: notch'u imlecin olduğu ekranda belirli sayfada açar (gizliyse önce gösterir).
    func openNotch(at page: NotchPage) {
        if isNotchHidden { showNotch() }
        if availablePages.contains(page) { ui.selectedPage = page }
        let mouse = NSEvent.mouseLocation
        let screenID = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            .flatMap { $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID }
        let model = panels.models.first { $0.displayID == screenID } ?? panels.models.first
        model?.tapped()
    }
}
