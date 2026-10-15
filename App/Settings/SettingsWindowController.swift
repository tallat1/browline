import AppKit
import SwiftUI

/// Ayarlar yalnız menü çubuğundan açılır. ⚠️ Faz 0: panelden pencere açmak uygulamayı
/// etkinleştirip kullanıcıyı tam ekran Space'inden atıyor; bu yüzden notch'ta ayar düğmesi yok.
@MainActor
final class SettingsWindowController {
    private let coordinator: AppCoordinator
    private var window: NSWindow?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        coordinator.settings.refreshLaunchAtLoginStatus()
        NSApp.activate()
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = String(localized: "NotchMVP Ayarları")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(coordinator: coordinator,
                                                                 settings: coordinator.settings))
        return window
    }
}
