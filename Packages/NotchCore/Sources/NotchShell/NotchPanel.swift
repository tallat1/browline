import AppKit

/// Etkinleştirmeyen, şeffaf, her Space'te duran notch paneli.
public final class NotchPanel: NSPanel {
    /// Faz 0: tam ekranda .screenSaver ile fark ölçülmedi; .screenSaver açılır menüleri,
    /// Control Center'ı ve parola diyaloğunu örttüğü için varsayılan bu.
    public static let defaultLevel = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)

    /// Yalnız bir metin alanına yazılırken true; aksi halde hover ve tıklama odağı çalar.
    public var wantsKeyForTextInput = false

    /// Panelin opak alanına gelen iki parmak kaydırma.
    var onScroll: ((NSEvent) -> Void)?

    /// Esc. NSPanel'in varsayılanı paneli kapatmak; notch kapanmamalı, yalnız durum değişmeli.
    var onCancel: (() -> Void)?

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        animationBehavior = .none
        level = Self.defaultLevel
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // ⚠️ ignoresMouseEvents BİLEREK atanmıyor: açıkça false atamak şeffaf piksel geçişini
        // kalıcı kapatır (DynamicNotchKit #48). Faz 0'da bu mod ölçüldü ve en az uyanmayı verdi.
    }

    override public var canBecomeKey: Bool { wantsKeyForTextInput }
    override public var canBecomeMain: Bool { false }

    /// Metin alanı için klavye. Açarken key yapılmaz; kullanıcı alana tıklayınca AppKit yapar.
    /// Kapatırken key durumu bırakılır: `resignKey` doğrudan çağrılmamalı (Apple), bu yüzden
    /// pencere aynı döngüde sıradan çıkarılıp geri konur; klavye öndeki uygulamaya döner.
    func setTextInput(_ active: Bool) {
        wantsKeyForTextInput = active
        guard !active, isKeyWindow else { return }
        let wasVisible = isVisible
        orderOut(nil)
        if wasVisible { orderFrontRegardless() }
    }

    /// Ajan uygulamada Düzen menüsü yok; ⌘C/V/X/A/Z kendiliğinden çalışmaz (Cyclop'taki sorun).
    /// Yalnız metin girişi açıkken eylem ilk yanıtlayıcıya gönderilir.
    override public func performKeyEquivalent(with event: NSEvent) -> Bool {
        if wantsKeyForTextInput,
           let action = Self.editAction(for: event.charactersIgnoringModifiers, modifiers: event.modifierFlags),
           NSApp.sendAction(action, to: nil, from: self) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    nonisolated static func editAction(for characters: String?, modifiers: NSEvent.ModifierFlags) -> Selector? {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), !flags.contains(.control), !flags.contains(.option) else { return nil }
        let shift = flags.contains(.shift)
        switch characters?.lowercased() {
        case "c": return shift ? nil : #selector(NSText.copy(_:))
        case "v": return shift ? nil : #selector(NSText.paste(_:))
        case "x": return shift ? nil : #selector(NSText.cut(_:))
        case "a": return shift ? nil : #selector(NSText.selectAll(_:))
        case "z": return shift ? Selector(("redo:")) : Selector(("undo:"))
        default: return nil
        }
    }

    override public func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override public func sendEvent(_ event: NSEvent) {
        if event.type == .scrollWheel { onScroll?(event) }
        super.sendEvent(event)
    }
}
