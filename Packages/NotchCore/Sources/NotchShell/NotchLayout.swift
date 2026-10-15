import CoreGraphics

/// Yerleşimin ayarlanabilir ölçüleri.
public struct NotchLayoutConfig: Equatable, Sendable {
    /// Açık durumun genişliği; ekrana sığmazsa ekran genişliği.
    public var openWidth: CGFloat = 560
    /// Açık durumda çentik bandının altındaki içerik yüksekliği.
    public var openContentHeight: CGFloat = 136
    /// Kompakt durumda çentiğin iki yanına eklenen kanat genişliği.
    public var compactWingWidth: CGFloat = 38
    /// Hover ipucunda (peek) şeklin büyümesi.
    public var peekGrowth = CGSize(width: 8, height: 4)
    /// Çentiksiz ekrandaki hap, içerik yokken.
    public var pillClosedWidth: CGFloat = 140

    public init() {}
}

/// Şeklin bulunduğu durum. Pencere boyutu değişmez; yalnız şekil bu boyutlar arasında akar.
public enum NotchPresentation: Equatable, Sendable {
    /// Gösterilecek bir şey yok: şekil donanım çentiğiyle aynı.
    case closed
    /// Canlı bir etkinlik var: çentiğin iki yanında kanatlar.
    case compact
    /// Hover ipucu: açılmadan önce hafif büyüme.
    case peek(compact: Bool)
    case open
}

/// Bir ekranın panel ve şekil ölçüleri. Tamamen ScreenMetrics'ten türetilir; sabit sayılar
/// yalnız çentiksiz ekrandaki hap ve açık durum içeriği içindir.
public struct NotchLayout: Equatable, Sendable {
    public enum Style: String, Sendable {
        case notch
        case pill
    }

    public static let closedTopRadius: CGFloat = 6
    public static let closedBottomRadius: CGFloat = 14
    public static let openTopRadius: CGFloat = 14
    public static let openBottomRadius: CGFloat = 24
    public static let pillOpenCornerRadius: CGFloat = 24

    public let style: Style
    public let notchRect: CGRect?
    /// Kapalı şeklin boyutu: çentikte gövde + iki kulak, hapta sabit genişlik.
    public let closedSize: CGSize
    public let openSize: CGSize
    /// Şeklin panel üst kenarından uzaklığı (hap menü bandının içinde asılı durur).
    public let topInset: CGFloat
    /// Sabit panel karesi, global koordinatta: en büyük durumu (açık) içerir.
    public let panelFrame: CGRect
    public let config: NotchLayoutConfig

    /// Çentik bandının yüksekliği: açık içerikte ilk satır bu bandın yanına yerleşir.
    public var bandHeight: CGFloat { notchRect?.height ?? closedSize.height }

    /// Çentiğin kapladığı genişlik (açık durumda içerik bu boşluğa yazılmaz).
    public var notchGapWidth: CGFloat { notchRect?.width ?? 0 }

    public static func make(metrics: ScreenMetrics, config: NotchLayoutConfig = .init()) -> NotchLayout {
        let screen = metrics.frame
        if let notch = metrics.notchRect {
            // Kulaklar gövdenin iki yanına taşar; gövde genişliği = gerçek çentik genişliği.
            let closed = CGSize(width: notch.width + 2 * closedTopRadius, height: notch.height)
            let openWidth = min(max(config.openWidth, closed.width + 2 * config.compactWingWidth + 80),
                                screen.width)
            let open = CGSize(width: openWidth, height: notch.height + config.openContentHeight)
            return NotchLayout(style: .notch, notchRect: notch, closedSize: closed, openSize: open,
                               topInset: 0,
                               panelFrame: panelFrame(midX: notch.midX, size: open, topInset: 0, in: screen),
                               config: config)
        }
        let bar = metrics.menuBarHeight > 0 ? metrics.menuBarHeight : 24
        let closed = CGSize(width: config.pillClosedWidth, height: max(bar - 6, 18))
        let open = CGSize(width: min(config.openWidth, screen.width), height: config.openContentHeight + closed.height)
        let inset: CGFloat = 3
        return NotchLayout(style: .pill, notchRect: nil, closedSize: closed, openSize: open, topInset: inset,
                           panelFrame: panelFrame(midX: screen.midX, size: open, topInset: inset, in: screen),
                           config: config)
    }

    private static func panelFrame(midX: CGFloat, size: CGSize, topInset: CGFloat, in screen: CGRect) -> CGRect {
        // Peek büyümesi açık boyuttan küçük kaldığı sürece ek pay gerekmez.
        let height = size.height + topInset
        var x = midX - size.width / 2
        x = min(max(x, screen.minX), screen.maxX - size.width)
        return CGRect(x: x, y: screen.maxY - height, width: size.width, height: height)
    }

    /// `wingWidth`: kompakt kanat genişliği; nil ise yapılandırmadaki dar kanat. Geniş kanat
    /// açık genişliği aşmayacak şekilde kırpılır, böylece panel karesi hiç değişmez.
    public func size(for presentation: NotchPresentation, wingWidth: CGFloat? = nil) -> CGSize {
        switch presentation {
        case .closed:
            return closedSize
        case .compact:
            return compactSize(wingWidth)
        case let .peek(compact):
            let base = compact ? compactSize(wingWidth) : closedSize
            return CGSize(width: base.width + config.peekGrowth.width, height: base.height + config.peekGrowth.height)
        case .open:
            return openSize
        }
    }

    public func clampedWingWidth(_ requested: CGFloat?) -> CGFloat {
        let maximum = max(0, (openSize.width - config.peekGrowth.width - closedSize.width) / 2)
        return min(requested ?? config.compactWingWidth, maximum)
    }

    private func compactSize(_ wingWidth: CGFloat?) -> CGSize {
        CGSize(width: closedSize.width + 2 * clampedWingWidth(wingWidth), height: closedSize.height)
    }

    /// Görünür şeklin global dikdörtgeni (hover sıcak bölgesi ve sürükleme hedefi için).
    public func shapeRect(for presentation: NotchPresentation, wingWidth: CGFloat? = nil) -> CGRect {
        let size = size(for: presentation, wingWidth: wingWidth)
        return CGRect(x: panelFrame.midX - size.width / 2, y: panelFrame.maxY - topInset - size.height,
                      width: size.width, height: size.height)
    }
}
