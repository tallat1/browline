import AppKit

// SwiftUI App yaşam döngüsü yerine düz AppKit: pencere katmanı tamamen elimizde kalsın.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)  // LSUIElement ile aynı; Info.plist yedeği
    app.run()
}
