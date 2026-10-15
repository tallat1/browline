import AppKit
import ApplicationServices

/// NX_SYSDEFINED medya tuşu kodları.
public enum MediaKey: Int, Sendable {
    case soundUp = 0
    case soundDown = 1
    case brightnessUp = 2
    case brightnessDown = 3
    case mute = 7
    case illuminationUp = 21
    case illuminationDown = 22
}

/// NX_SYSDEFINED olayının data1 alanı: üst 16 bit tuş kodu, sonra durum (0xA basma, 0xB bırakma)
/// ve en alt bit tekrar.
public struct MediaKeyEvent: Equatable, Sendable {
    public let keyCode: Int
    public let isDown: Bool
    public let isRepeat: Bool

    public static func decode(data1: Int) -> MediaKeyEvent {
        let flags = data1 & 0xFFFF
        return MediaKeyEvent(keyCode: (data1 & 0xFFFF_0000) >> 16,
                             isDown: (flags & 0xFF00) >> 8 == 0xA,
                             isRepeat: flags & 0x1 == 1)
    }
}

/// Aktif CGEventTap: işlenen medya tuşunu yutar, böylece sistem HUD'ı hiç çizilmez.
/// Erişilebilirlik izni ister ve App Sandbox ile uyumsuzdur (Apple DTS). İşlenemeyen tuş
/// (oynat/duraklat, klavye ışığı, ayarlanamayan çıkış) olduğu gibi geçirilir.
@MainActor
final class MediaKeyTap {
    /// true dönerse tuş işlendi ve yutulur.
    var handler: ((_ key: MediaKey, _ isRepeat: Bool, _ fineStep: Bool) -> Bool)?
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    /// Basması yutulan tuşun bırakması da yutulur; yoksa sistem yarım bir olay görür.
    private var swallowedKeyCodes: Set<Int> = []

    var isRunning: Bool { port != nil }

    func start() -> Bool {
        guard port == nil else { return true }
        let mask = CGEventMask(1) << 14  // NX_SYSDEFINED; CGEventType'ta karşılığı yok
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                           options: .defaultTap, eventsOfInterest: mask,
                                           callback: mediaKeyTapCallback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            return false
        }
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.port = port
        self.source = source
        return true
    }

    func stop() {
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        port = nil
        source = nil
        swallowedKeyCodes.removeAll()
    }

    /// true dönerse olay yutulur.
    fileprivate func shouldSwallow(eventType: UInt32, subtype: Int16?, data1: Int, fineStep: Bool) -> Bool {
        // İşletim sistemi yavaş geri çağrıda tap'i kapatır; hemen yeniden aç (boring.notch 2.7.3 açığı).
        if eventType == CGEventType.tapDisabledByTimeout.rawValue || eventType == CGEventType.tapDisabledByUserInput.rawValue {
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return false
        }
        guard eventType == 14, subtype == 8 else { return false }
        let decoded = MediaKeyEvent.decode(data1: data1)
        guard decoded.isDown else { return swallowedKeyCodes.remove(decoded.keyCode) != nil }
        guard let key = MediaKey(rawValue: decoded.keyCode),
              handler?(key, decoded.isRepeat, fineStep) == true else { return false }
        swallowedKeyCodes.insert(decoded.keyCode)
        return true
    }
}

/// Kaynak ana run loop'a eklendi; geri çağrı ana iş parçacığında gelir.
private func mediaKeyTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                 refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<MediaKeyTap>.fromOpaque(refcon).takeUnretainedValue()
    // CGEvent Sendable değil; ana aktöre yalnız değer tipleri geçer.
    let nsEvent = type.rawValue == 14 ? NSEvent(cgEvent: event) : nil
    let eventType = type.rawValue
    let subtype = nsEvent.map { $0.subtype.rawValue }
    let data1 = nsEvent?.data1 ?? 0
    let fine = event.flags.contains(.maskAlternate) && event.flags.contains(.maskShift)
    let swallow = MainActor.assumeIsolated {
        tap.shouldSwallow(eventType: eventType, subtype: subtype, data1: data1, fineStep: fine)
    }
    return swallow ? nil : Unmanaged.passUnretained(event)
}
