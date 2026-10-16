import AppKit
import Integrations

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    // Menü çubuğu AppDelegate+StatusMenu.swift'te; paylaşılan üyeler bu yüzden private değil.
    let coordinator = AppCoordinator()
    lazy var settingsWindow = SettingsWindowController(coordinator: coordinator)
    private lazy var onboardingWindow = OnboardingWindowController(coordinator: coordinator)
    var statusItem: NSStatusItem?
    /// URL olayı uygulamayı öne alır; odak bu uygulamaya geri verilir.
    private var lastExternalApp: NSRunningApplication?
    private var lastURLHandledAt: Date?
    #if DEBUG
    private lazy var debugChannel = DebugCommandChannel(coordinator: coordinator)
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        HelperQuarantine.clear()
        coordinator.start()
        #if DEBUG
        debugChannel.start()
        #endif
        installStatusItem()
        coordinator.onStatusIconChange = { [weak self] in self?.updateStatusIcon() }
        updateStatusIcon()
        trackFrontmostApplication()
        coordinator.openSettings = { [weak self] in self?.settingsWindow.show() }
        coordinator.closeSettings = { [weak self] in self?.settingsWindow.close() }
        #if DEBUG
        // Görüntü için: menüyü açar, 3 sn sonra kapatır (menü izleme döngüsünde ana kuyruk işler).
        coordinator.showStatusMenuForCapture = { [weak self] in
            guard let item = self?.statusItem, let menu = item.menu else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { menu.cancelTracking() }
            item.button?.performClick(nil)
        }
        #endif
        coordinator.openOnboarding = { [weak self] in self?.onboardingWindow.show() }
        #if DEBUG
        coordinator.onboardingStepForDebug = { [weak self] step in self?.onboardingWindow.model.step = step }
        coordinator.closeOnboarding = { [weak self] in self?.onboardingWindow.close() }
        #endif
        if !coordinator.settings.hasCompletedOnboarding { onboardingWindow.show() }
    }

    // MARK: - URL şeması

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(coordinator.handleURL)
        lastURLHandledAt = .now
        returnFocusIfNeeded()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Etkinleşme URL olayından sonra da gelebiliyor.
        guard let handledAt = lastURLHandledAt, Date.now.timeIntervalSince(handledAt) < 1 else { return }
        returnFocusIfNeeded()
    }

    private func trackFrontmostApplication() {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ownPID { lastExternalApp = app }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                guard let app, app.processIdentifier != ownPID else { return }
                self?.lastExternalApp = app
            }
        }
    }

    /// `open browline://…` (−g olmadan) ajan uygulamayı etkinleştirir ve kullanıcının odağını alır.
    /// Açık ayar penceresi yoksa odak önceki uygulamaya geri verilir.
    private func returnFocusIfNeeded() {
        guard NSApp.isActive, !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeKey }),
              let app = lastExternalApp, !app.isTerminated else { return }
        NSApp.yieldActivation(to: app)
        app.activate()
    }

    /// Menü çubuğu simgesi taşma (») denetiminin arkasında kalırsa: uygulamayı yeniden açmak
    /// ayarları getirir (macOS 27 tek pencereli menü çubuğu).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow.show()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
    }
}
