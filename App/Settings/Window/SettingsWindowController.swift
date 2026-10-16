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
        if window.isMiniaturized { window.deminiaturize(nil) }
        if !window.isVisible { window.center() }
        // Ajan uygulama notch'tan (etkinleştirmeyen panel) açınca macOS 14+ işbirlikçi etkinleştirmeyi
        // reddedebiliyor: pencere öndeki uygulamanın arkasında, "en altta" açılıyordu (kullanıcı
        // 2026-10-16). orderFrontRegardless uygulama etkin olmasa da pencereyi öne alır; ardından
        // etkinleştirme istenir, reddedilse de pencere görünür kalır.
        window.orderFrontRegardless()
        window.makeKey()
        NSApp.activate()
    }

    func close() {
        window?.close()
    }

    private func makeWindow() -> NSWindow {
        // Sistem Ayarları gibi: kenar çubuğu başlık çubuğunun altına uzanır.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.contentMinSize = NSSize(width: 760, height: 540)
        window.title = String(localized: "Browline Ayarları")
        window.isReleasedWhenClosed = false
        // Başka Space'te açık kalmışsa oraya geçmek yerine bulunulan Space'e gelsin.
        window.collectionBehavior = [.moveToActiveSpace]
        window.contentView = NSHostingView(rootView: SettingsView(coordinator: coordinator,
                                                                 settings: coordinator.settings))
        return window
    }
}
