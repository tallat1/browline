import Darwin

/// ⚠️ Private API: ekranı izleyen (kaydeden, paylaşan, yansıtan) bir süreç var mı (SkyLight
/// `CGSIsScreenWatcherPresent`). Public karşılığı yok; macOS'un mor kayıt simgesiyle aynı an.
/// Doğrulama (2026-10-16, macOS 27): 1×1 piksellik 2 sn'lik `screencapture -v` boyunca 1, öncesi ve
/// sonrası 0. Sembol yoksa özellik kapanır, uygulama çökmez.
public enum ScreenWatcher {
    private typealias PresentFunction = @convention(c) () -> Bool

    private struct Symbols: @unchecked Sendable {
        let present: PresentFunction
    }

    private static let symbols: Symbols? = {
        let path = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
        guard let handle = dlopen(path, RTLD_LAZY), let present = dlsym(handle, "CGSIsScreenWatcherPresent") else {
            return nil
        }
        return Symbols(present: unsafeBitCast(present, to: PresentFunction.self))
    }()

    public static var isAvailable: Bool { symbols != nil }

    /// Sembol yoksa nil.
    public static func isPresent() -> Bool? { symbols?.present() }
}
