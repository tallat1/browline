import AppKit

/// Bir ekranın notch hesabı için gereken ölçüleri. NSScreen'den bir kez okunur;
/// yerleşim hesabı bu değer tipiyle çalıştığı için test edilebilir.
public struct ScreenMetrics: Equatable, Sendable {
    public var displayID: CGDirectDisplayID
    public var name: String
    public var isBuiltIn: Bool
    /// Global koordinatlar (AppKit, alt-sol köken).
    public var frame: CGRect
    public var visibleFrame: CGRect
    public var safeAreaTop: CGFloat
    public var auxiliaryTopLeft: CGRect?
    public var auxiliaryTopRight: CGRect?
    /// Ekranın kalıcı kimliği (CoreGraphics UUID). displayID yeniden bağlanınca değişebilir;
    /// ekran başına ayar bununla saklanır.
    public var persistentID: String

    public init(displayID: CGDirectDisplayID, name: String, isBuiltIn: Bool, frame: CGRect,
                visibleFrame: CGRect, safeAreaTop: CGFloat,
                auxiliaryTopLeft: CGRect?, auxiliaryTopRight: CGRect?, persistentID: String? = nil) {
        self.persistentID = persistentID ?? "display-\(displayID)"
        self.displayID = displayID
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.safeAreaTop = safeAreaTop
        self.auxiliaryTopLeft = auxiliaryTopLeft
        self.auxiliaryTopRight = auxiliaryTopRight
    }

    /// Çentik dikdörtgeni, global koordinatta. Kamera yuvası yoksa ya da kullanıcı
    /// "çentiğin altında" çözünürlük seçtiyse (safeAreaTop 0) nil.
    /// Konum için frame.midX değil yardımcı alanların iç kenarları: çoklu ekranda
    /// yerleşik ekran (0,0) noktasında olmayabilir.
    public var notchRect: CGRect? {
        guard safeAreaTop > 0, let left = auxiliaryTopLeft, let right = auxiliaryTopRight,
              right.minX > left.maxX else { return nil }
        return CGRect(x: left.maxX, y: frame.maxY - safeAreaTop,
                      width: right.minX - left.maxX, height: safeAreaTop)
    }

    /// Menü çubuğu otomatik gizliyse 0. NSStatusBar.system.thickness bu değerle aynı değil.
    public var menuBarHeight: CGFloat { frame.maxY - visibleFrame.maxY }
}

extension NSScreen {
    public var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// Apple belgesine göre kapak kapalıyken hiçbir ekran yerleşik işaretlenmeyebilir.
    public var isBuiltIn: Bool {
        displayID.map { CGDisplayIsBuiltin($0) != 0 } ?? false
    }

    public var persistentID: String? {
        guard let displayID, let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return nil
        }
        return CFUUIDCreateString(nil, uuid) as String
    }

    /// Değerler ölçeklemeye göre değişir (Faz 0: 24,5–38 pt); her ekran değişiminde yeniden okunur.
    @MainActor
    public var metrics: ScreenMetrics? {
        guard let displayID else { return nil }
        return ScreenMetrics(displayID: displayID, name: localizedName, isBuiltIn: isBuiltIn,
                             frame: frame, visibleFrame: visibleFrame,
                             safeAreaTop: safeAreaInsets.top,
                             auxiliaryTopLeft: auxiliaryTopLeftArea,
                             auxiliaryTopRight: auxiliaryTopRightArea,
                             persistentID: persistentID)
    }
}
