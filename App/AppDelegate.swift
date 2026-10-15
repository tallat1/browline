import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let coordinator = AppCoordinator()
    private lazy var settingsWindow = SettingsWindowController(coordinator: coordinator)
    private var statusItem: NSStatusItem?
    #if DEBUG
    private lazy var debugChannel = DebugCommandChannel(coordinator: coordinator)
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator.start()
        #if DEBUG
        debugChannel.start()
        #endif
        installStatusItem()
        if !coordinator.settings.hasCompletedOnboarding { settingsWindow.show() }
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

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let title = NSMenuItem(title: "NotchMVP", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        let source = NSMenuItem(title: coordinator.nowPlayingSourceDescription, action: nil, keyEquivalent: "")
        source.isEnabled = false
        menu.addItem(source)
        menu.addItem(.separator())
        menu.addItem(action(String(localized: "Ayarlar…"), key: ",") { [weak self] in self?.settingsWindow.show() })
        menu.addItem(action(String(localized: "Paneli yeniden kur")) { [weak self] in self?.coordinator.panels.rebuild(trigger: "menü") })
        menu.addItem(.separator())
        menu.addItem(action(String(localized: "Çık"), key: "q") { NSApp.terminate(nil) })
    }

    private func action(_ title: String, key: String = "", _ handler: @escaping () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(MenuAction.run), keyEquivalent: key)
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
