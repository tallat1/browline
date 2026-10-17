import AppKit
import Integrations

// SwiftUI App yaşam döngüsü yerine düz AppKit: pencere katmanı tamamen elimizde kalsın.
MainActor.assumeIsolated {
    // Eski kimlikten (com.talatozcoban.notchmvp) ayar ve veri: AppSettings okunmadan önce.
    if let identifier = Bundle.main.bundleIdentifier {
        LegacyMigration.run(identifier: identifier, defaults: .standard,
                            supportDirectory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
    }
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    TerminationSignals.install()  // kill/⌃C da applicationWillTerminate'ten geçsin
    app.setActivationPolicy(.accessory)  // LSUIElement ile aynı; Info.plist yedeği
    app.run()
}
