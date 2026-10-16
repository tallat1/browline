import AppKit
import Integrations

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let coordinator = AppCoordinator()
    private lazy var settingsWindow = SettingsWindowController(coordinator: coordinator)
    private lazy var onboardingWindow = OnboardingWindowController(coordinator: coordinator)
    private var statusItem: NSStatusItem?
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

    // MARK: - Menü çubuğu

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled",
                                     accessibilityDescription: "Browline")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    /// Native kalıp: başlık bölümü, simgeli öğeler. Teknik durum ve "Paneli yeniden kur" yalnız menü
    /// Option ile açılınca (gelişmiş öğeler); günlük kullanımda gürültü olmasın.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(.sectionHeader(title: "Browline"))
        // O an geçerli durum satırları: yoksa menü eskisi kadar kısa (2026-10-16 tasarım denetimi).
        let lines = statusLines()
        if !lines.isEmpty {
            lines.forEach(menu.addItem)
            menu.addItem(.separator())
        }
        menu.addItem(openNotchMenu())
        menu.addItem(hideNotchItem())
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
        menu.addItem(action(String(localized: "Ayarlar…"), key: ",", symbol: "gearshape") { [weak self] in
            self?.settingsWindow.show()
        })
        menu.addItem(action(String(localized: "Çık"), key: "q") { NSApp.terminate(nil) })
    }

    /// Simge: mikrofon sessizken çizgili mikrofon, notch gizliyken soluk.
    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        let muted = coordinator.isMicrophoneMuted
        button.image = NSImage(systemSymbolName: muted ? "mic.slash.fill" : "rectangle.topthird.inset.filled",
                               accessibilityDescription: "Browline")
        button.appearsDisabled = coordinator.isNotchHidden
        button.toolTip = coordinator.isNotchHidden ? String(localized: "Notch gizli") : (muted ? String(localized: "Mikrofon kapalı") : nil)
    }

    /// Çalan şarkı, süren CI, Claude limiti; basınca ilgili yere gider.
    private func statusLines() -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        let settings = coordinator.settings
        if settings.nowPlayingEnabled, let info = coordinator.nowPlaying.info {
            let detail = [info.artist, info.bundleIdentifier.flatMap(MediaPage.appName(for:))].compactMap { $0 }.filter { !$0.isEmpty }
            items.append(statusItem(title: info.title, subtitle: detail.joined(separator: " · "),
                                    symbol: info.isPlaying ? "play.fill" : "pause.fill") { [weak self] in
                self?.coordinator.openNotch(at: .now)
            })
        }
        if settings.ciEnabled, let run = coordinator.ci.activeRuns.first {
            let minutes = Int(Date.now.timeIntervalSince(run.createdAt) / 60)
            items.append(statusItem(title: "CI · \(run.repositoryName)",
                                    subtitle: String(localized: "\(run.workflow) · \(minutes) dk sürüyor"),
                                    symbol: "hammer.fill") { [weak self] in
                if let url = run.url { NSWorkspace.shared.open(url) } else { self?.coordinator.openNotch(at: .ci) }
            })
        }
        if settings.claudeUsageEnabled, let usage = coordinator.claudeUsage.usage, let session = usage.fiveHour?.usedPercentage {
            let week = usage.sevenDay.map { String(localized: "hafta \(NowFormat.percent($0.usedPercentage))") }
            items.append(statusItem(title: String(localized: "Claude · oturum \(NowFormat.percent(session))"),
                                    subtitle: week ?? "", symbol: "sparkles") { [weak self] in
                self?.coordinator.openNotch(at: .claude)
            })
        }
        return items
    }

    private func statusItem(title: String, subtitle: String, symbol: String, _ handler: @escaping () -> Void) -> NSMenuItem {
        let item = action(title, symbol: symbol, handler)
        if #available(macOS 14.4, *) {
            if !subtitle.isEmpty { item.subtitle = subtitle }
        } else if !subtitle.isEmpty {
            item.title = "\(title) · \(subtitle)"
        }
        return item
    }

    /// Notch'u imlecin olduğu ekranda istenen bölümde açar; kapak kapalıyken de çalışır.
    private func openNotchMenu() -> NSMenuItem {
        let item = NSMenuItem(title: String(localized: "Notch'u aç"), action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: nil)
        let submenu = NSMenu()
        let destinations: [(String, String, NotchPage)] = [
            (String(localized: "Şimdi"), "house", .now),
            (String(localized: "Raf"), "tray.full", .shelf),
            (String(localized: "Pano"), "doc.on.clipboard", .clipboard),
            (String(localized: "Takvim"), "calendar", .calendar),
            (String(localized: "Araçlar"), "wrench.and.screwdriver", coordinator.ui.lastPage[.tools] ?? .notes),
            (String(localized: "Durum"), "gauge.with.dots.needle.33percent", coordinator.ui.lastPage[.status] ?? .system),
        ]
        let available = coordinator.availablePages
        for (title, symbol, page) in destinations where available.contains(page) {
            submenu.addItem(action(title, symbol: symbol) { [weak self] in self?.coordinator.openNotch(at: page) })
        }
        item.submenu = submenu
        return item
    }

    /// Gizliyken "Notch'u göster" (ne zamana kadar gizli olduğuyla), değilse süreli gizleme.
    private func hideNotchItem() -> NSMenuItem {
        if coordinator.isNotchHidden {
            let item = action(String(localized: "Notch'u göster"), symbol: "eye") { [weak self] in self?.coordinator.showNotch() }
            if #available(macOS 14.4, *), let until = coordinator.settings.notchHiddenUntil, until != .distantFuture {
                // Saate ek getirmeyen biçim: "16:12'a" saate göre yanlış ek alır.
                item.subtitle = String(localized: "Geri gelme: \(until.formatted(date: .omitted, time: .shortened))")
            }
            return item
        }
        let item = NSMenuItem(title: String(localized: "Notch'u gizle"), action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: nil)
        let submenu = NSMenu()
        submenu.addItem(action(String(localized: "1 saat")) { [weak self] in self?.coordinator.hideNotch(for: 3600) })
        submenu.addItem(action(String(localized: "Yarın sabaha kadar")) { [weak self] in self?.coordinator.hideNotchUntilTomorrow() })
        submenu.addItem(action(String(localized: "Gösterene kadar")) { [weak self] in self?.coordinator.hideNotch(for: nil) })
        item.submenu = submenu
        return item
    }

    /// Uyanık tutma süreleri; notch'taki düğme süresiz açar.
    private func keepAwakeMenu() -> NSMenuItem {
        let awake = coordinator.keepAwake
        let item = NSMenuItem(title: Self.keepAwakeTitle(awake), action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: awake.isActive ? "cup.and.saucer.fill" : "cup.and.saucer",
                             accessibilityDescription: nil)
        let submenu = NSMenu()
        let reason = String(localized: "Browline: uyanık tut")
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
