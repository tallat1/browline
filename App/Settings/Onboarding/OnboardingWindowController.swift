import AppKit
import Integrations
import NotchShell
import SwiftUI

/// Karşılama penceresi: ilk açılışta ya da Ayarlar › Genel'den.
@MainActor
final class OnboardingWindowController {
    private let coordinator: AppCoordinator
    private var window: NSWindow?
    let model = OnboardingModel()

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    func show() {
        model.step = 0
        let window = self.window ?? makeWindow()
        self.window = window
        if !window.isVisible { window.center() }
        window.orderFrontRegardless()
        window.makeKey()
        NSApp.activate()
    }

    func close() {
        window?.close()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 480),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = String(localized: "Hoş geldiniz")
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.contentView = NSHostingView(rootView: OnboardingView(coordinator: coordinator, model: model) { [weak self] in
            self?.coordinator.settings.hasCompletedOnboarding = true
            self?.close()
        })
        return window
    }
}
