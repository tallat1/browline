import CoreGraphics
import Darwin

/// ⚠️ Private API: yerleşik ekran parlaklığı (DisplayServices). Apple silicon'da güvenilir public
/// yol yok (IODisplayConnect M1'de desteklenmiyor). Semboller çalışma anında dlsym ile çözülür;
/// bulunamazsa özellik kapanır, uygulama çökmez. Bu modül private API'nin tek yeri.
public enum DisplayBrightness {
    private typealias GetFunction = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFunction = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private struct Symbols: @unchecked Sendable {
        let get: GetFunction
        let set: SetFunction
    }

    private static let symbols: Symbols? = {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard let handle = dlopen(path, RTLD_LAZY),
              let get = dlsym(handle, "DisplayServicesGetBrightness"),
              let set = dlsym(handle, "DisplayServicesSetBrightness") else { return nil }
        return Symbols(get: unsafeBitCast(get, to: GetFunction.self), set: unsafeBitCast(set, to: SetFunction.self))
    }()

    public static var isAvailable: Bool { symbols != nil }

    /// 0…1; ekran desteklemiyorsa nil.
    public static func brightness(of display: CGDirectDisplayID) -> Float? {
        guard let symbols else { return nil }
        var value: Float = 0
        guard symbols.get(display, &value) == 0 else { return nil }
        return value
    }

    @discardableResult
    public static func setBrightness(_ value: Float, of display: CGDirectDisplayID) -> Bool {
        guard let symbols else { return false }
        return symbols.set(display, min(max(value, 0), 1)) == 0
    }
}
