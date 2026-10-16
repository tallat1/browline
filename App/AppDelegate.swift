import AppKit
import Integrations

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let coordinator = AppCoordinator()
    private lazy var settingsWindow = SettingsWindowController(coordinator: coordinator)
    private var statusItem: NSStatusItem?
    /// URL olayı uygulamayı öne alır; odak bu uygulamaya geri verilir.
    private var lastExternalApp: NSRunningApplication?
    private var lastURLHandledAt: Date?
    #if DEBUG
    private lazy var debugChannel = DebugCommandChannel(coordinator: coordinator)
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator.start()
        #if DEBUG
        debugChannel.start()
        #endif
        installStatusItem()
        trackFrontmostApplication()
        coordinator.openSettings = { [weak self] in self?.settingsWindow.show() }
        coordinator.closeSettings = { [weak self] in self?.settingsWindow.close() }
        if !coordinator.settings.hasCompletedOnboarding { settingsWindow.show() }
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

    /// `open notchmvp://…` (−g olmadan) ajan uygulamayı etkinleştirir ve kullanıcının odağını alır.
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

    // MARK: - Menü çubuğu

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled",
                                     accessibilityDescription: "NotchMVP")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    /// Native kalıp: başlık bölümü, simgeli öğeler. Teknik durum ve "Paneli yeniden kur" yalnız menü
    /// Option ile açılınca (gelişmiş öğeler); günlük kullanımda gürültü olmasın.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(.sectionHeader(title: "NotchMVP"))
        menu.addItem(action(String(localized: "Ayarlar…"), key: ",", symbol: "gearshape") { [weak self] in
            self?.settingsWindow.show()
        })
        if coordinator.settings.keepAwakeEnabled { menu.addItem(keepAwakeMenu()) }
        let microphone = coordinator.microphone
        if coordinator.settings.meetingControlsEnabled, microphone.canMute {
            let item = action(microphone.isMuted ? String(localized: "Mikrofonu aç") : String(localized: "Mikrofonu sessize al"),
                              symbol: microphone.isMuted ? "mic.fill" : "mic.slash") { microphone.toggleMute() }
            // Genel kısayol menüde de görünsün (menü açıkken de aynı işi yapar).
            let shortcut = coordinator.settings.micShortcut
            if shortcut != .off, !coordinator.ui.micShortcutUnavailable {
                item.keyEquivalent = "m"
                item.keyEquivalentModifierMask = shortcut.menuModifiers
            }
            menu.addItem(item)
        }
        if NSEvent.modifierFlags.contains(.option) {
            menu.addItem(.separator())
            menu.addItem(.sectionHeader(title: String(localized: "Gelişmiş")))
            let source = NSMenuItem(title: coordinator.nowPlayingSourceDescription, action: nil, keyEquivalent: "")
            source.isEnabled = false
            menu.addItem(source)
            menu.addItem(action(String(localized: "Paneli yeniden kur"), symbol: "arrow.clockwise") { [weak self] in
                self?.coordinator.panels.rebuild(trigger: "menü")
            })
        }
        menu.addItem(.separator())
        menu.addItem(action(String(localized: "Çık"), key: "q") { NSApp.terminate(nil) })
    }

    /// Uyanık tutma süreleri; notch'taki düğme süresiz açar.
    private func keepAwakeMenu() -> NSMenuItem {
        let awake = coordinator.keepAwake
        let item = NSMenuItem(title: Self.keepAwakeTitle(awake), action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: awake.isActive ? "cup.and.saucer.fill" : "cup.and.saucer",
                             accessibilityDescription: nil)
        let submenu = NSMenu()
        let reason = String(localized: "NotchMVP: uyanık tut")
        for (title, duration) in [(String(localized: "30 dakika"), Duration.seconds(30 * 60)),
                                  (String(localized: "1 saat"), .seconds(60 * 60)),
                                  (String(localized: "2 saat"), .seconds(2 * 60 * 60))] {
            submenu.addItem(action(title) { awake.start(for: duration, reason: reason) })
        }
        let forever = action(String(localized: "Kapatana kadar")) { awake.start(reason: reason) }
        forever.state = awake.isActive && awake.endsAt == nil ? .on : .off
        submenu.addItem(forever)
        if awake.isActive {
            submenu.addItem(.separator())
            submenu.addItem(action(String(localized: "Kapat"), symbol: "xmark") { awake.stop() })
        }
        item.submenu = submenu
        return item
    }

    /// Açıkken kalan süre de yazılır: menü her açılışta yeniden kurulur.
    private static func keepAwakeTitle(_ awake: KeepAwake) -> String {
        guard awake.isActive else { return String(localized: "Uyanık tut") }
        guard let endsAt = awake.endsAt else { return String(localized: "Uyanık tutuluyor · kapatana kadar") }
        let minutes = Int((max(0, endsAt.timeIntervalSinceNow) / 60).rounded(.up))
        return String(localized: "Uyanık tutuluyor · \(minutes) dk kaldı")
    }

    private func action(_ title: String, key: String = "", symbol: String? = nil,
                        _ handler: @escaping () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(MenuAction.run), keyEquivalent: key)
        item.image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        let target = MenuAction(handler)
        item.target = target
        item.representedObject = target  // hedef zayıf tutulur; nesneyi öğe yaşatır
        return item
    }
}

@MainActor
private final class MenuAction: NSObject {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func run() { handler() }
}
