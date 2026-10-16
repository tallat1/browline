import AppKit
import Carbon.HIToolbox

/// Sistem genelinde klavye kısayolu: hangi uygulama öndeyse olsun çalışır. Carbon
/// `RegisterEventHotKey`: Erişilebilirlik ya da Giriş İzleme izni İSTEMEZ (olay dinleyicisi değil,
/// yalnız bu tuş birleşimi bize ayrılır). Birleşim başka uygulamada kayıtlıysa kayıt başarısız olur.
@MainActor
final class GlobalShortcut {
    /// Kısayol seçenekleri. ⌥⌘M çoğu uygulamada "tüm pencereleri küçült", ⇧⌘M Teams'in kendi sessize
    /// alması: ikisi de bilerek yok.
    enum Preset: String, CaseIterable, Identifiable, Sendable {
        case off
        case controlOptionM
        case controlOptionCommandM

        var id: String { rawValue }

        var title: String {
            switch self {
            case .off: String(localized: "Kapalı")
            case .controlOptionM: "⌃⌥M"
            case .controlOptionCommandM: "⌃⌥⌘M"
            }
        }

        /// Carbon tuş kodu ve değiştiriciler.
        var combination: (keyCode: UInt32, modifiers: UInt32)? {
            switch self {
            case .off: nil
            case .controlOptionM: (UInt32(kVK_ANSI_M), UInt32(controlKey | optionKey))
            case .controlOptionCommandM: (UInt32(kVK_ANSI_M), UInt32(controlKey | optionKey | cmdKey))
            }
        }

        /// Menü öğesinde gösterim için.
        var menuModifiers: NSEvent.ModifierFlags {
            switch self {
            case .off: []
            case .controlOptionM: [.control, .option]
            case .controlOptionCommandM: [.control, .option, .command]
            }
        }
    }

    private static let signature: OSType = 0x4E_4D_56_50  // "NMVP"
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var eventHandler: EventHandlerRef?

    private let id: UInt32
    private var hotKey: EventHotKeyRef?

    init(id: UInt32, action: @escaping () -> Void) {
        self.id = id
        Self.handlers[id] = action
    }

    /// Önceki kaydı bırakır, yenisini kurar. Başarısızsa (başka uygulama kullanıyor) false.
    @discardableResult
    func register(_ preset: Preset) -> Bool {
        unregister()
        guard let combination = preset.combination else { return true }
        Self.installHandlerIfNeeded()
        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(combination.keyCode, combination.modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &reference)
        guard status == noErr, let reference else { return false }
        hotKey = reference
        return true
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }

    private static func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr, hotKeyID.signature == GlobalShortcut.signature else { return OSStatus(eventNotHandledErr) }
            // Carbon olayları ana iş parçacığında gelir.
            MainActor.assumeIsolated { GlobalShortcut.handlers[hotKeyID.id]?() }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, nil, &eventHandler)
    }
}
