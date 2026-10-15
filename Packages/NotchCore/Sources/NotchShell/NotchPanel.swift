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

    override public func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override public func sendEvent(_ event: NSEvent) {
        if event.type == .scrollWheel { onScroll?(event) }
        super.sendEvent(event)
    }
}
