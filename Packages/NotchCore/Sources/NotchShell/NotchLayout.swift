import CoreGraphics

/// Yerleşimin ayarlanabilir ölçüleri.
public struct NotchLayoutConfig: Equatable, Sendable {
    /// Açık durumun varsayılan genişliği; ekrana sığmazsa ekran genişliği.
    public var openWidth: CGFloat = 560
    /// Açık durumda çentik bandının altındaki varsayılan içerik yüksekliği.
    public var openContentHeight: CGFloat = 136
    /// İçerik kendi boyunu isteyebilir (kare ayna, geniş takvim); panel karesi bu üst sınırı kapsar.
    public var maxOpenWidth: CGFloat = 680
    public var maxOpenContentHeight: CGFloat = 380
    /// Kompakt durumda çentiğin iki yanına eklenen kanat genişliği.
    public var compactWingWidth: CGFloat = 44
    /// Hover ipucunda (peek) şeklin büyümesi.
    public var peekGrowth = CGSize(width: 8, height: 4)
    /// Çentiksiz ekrandaki hap, içerik yokken.
    public var pillClosedWidth: CGFloat = 140
    /// Açık içeriğin görünen kenardan (kulak eğrisinin bittiği yerden) uzaklığı.
    public var contentMargin: CGFloat = 20
    public var contentBottomMargin: CGFloat = 16

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
        /// Çentiksiz ekranda menü çubuğu bandında asılı hap.
        case pill
        /// Menü çubuğunun altında, içerikten ayrık kart; yalnız gösterecek bir şey varken görünür.
        case floating
    }

    /// Yüzen kartın menü çubuğundan uzaklığı.
    public static let floatingGap: CGFloat = 8
    public static let floatingClosedHeight: CGFloat = 30

    public static let closedTopRadius: CGFloat = 6
    public static let closedBottomRadius: CGFloat = 14
    public static let openTopRadius: CGFloat = 14
    public static let openBottomRadius: CGFloat = 24
    public static let pillOpenCornerRadius: CGFloat = 24

    public let style: Style
    public let notchRect: CGRect?
    /// Kapalı şeklin boyutu: çentikte gövde + iki kulak, hapta sabit genişlik.
    public let closedSize: CGSize
    /// İçerik bir boy istemediğinde açık boyut.
    public let openSize: CGSize
    /// İstenebilecek en büyük açık boyut; panel karesi bunu kapsar.
    public let maxOpenSize: CGSize
    /// Şeklin panel üst kenarından uzaklığı (hap menü bandının içinde asılı durur).
    public let topInset: CGFloat
    /// Sabit panel karesi, global koordinatta: en büyük durumu (açık) içerir.
    public let panelFrame: CGRect
    public let config: NotchLayoutConfig

    /// Çentik bandının yüksekliği: açık içerikte ilk satır bu bandın yanına yerleşir.
    public var bandHeight: CGFloat { notchRect?.height ?? closedSize.height }

    /// Çentiğin kapladığı genişlik (açık durumda içerik bu boşluğa yazılmaz).
    public var notchGapWidth: CGFloat { notchRect?.width ?? 0 }

    /// Açık içeriğin çerçeveden yatay boşluğu. Çentikte görünen gövde, üst kulak yarıçapı kadar
    /// içeride başlar; boşluk o noktadan ölçülür, yoksa içerik görünen kenara yapışır.
    public var openHorizontalInset: CGFloat {
        (style == .notch ? Self.openTopRadius : 0) + config.contentMargin
    }

    /// `floating`: true ise ekranın çentiği olsa da yüzen kart.
    public static func make(metrics: ScreenMetrics, config: NotchLayoutConfig = .init(),
                            floating: Bool = false) -> NotchLayout {
        let screen = metrics.frame
        if floating {
            // Menü çubuğu otomatik gizliyse 0; kart o zaman ekranın üst kenarından aralıklı durur.
            let inset = metrics.menuBarHeight + floatingGap
            let closed = CGSize(width: config.pillClosedWidth, height: floatingClosedHeight)
            let open = CGSize(width: min(config.openWidth, screen.width - 2 * floatingGap),
                              height: config.openContentHeight + closed.height)
            let maximum = maxSize(closed: closed, open: open, band: closed.height, config: config,
                                  screenWidth: screen.width - 2 * floatingGap)
            return NotchLayout(style: .floating, notchRect: nil, closedSize: closed, openSize: open,
                               maxOpenSize: maximum, topInset: inset,
                               panelFrame: panelFrame(midX: screen.midX, size: maximum, topInset: inset, in: screen),
                               config: config)
        }
        if let notch = metrics.notchRect {
            // Kulaklar gövdenin iki yanına taşar; gövde genişliği = gerçek çentik genişliği.
            let closed = CGSize(width: notch.width + 2 * closedTopRadius, height: notch.height)
            let openWidth = min(max(config.openWidth, closed.width + 2 * config.compactWingWidth + 80),
                                screen.width)
            let open = CGSize(width: openWidth, height: notch.height + config.openContentHeight)
            let maximum = maxSize(closed: closed, open: open, band: notch.height, config: config, screenWidth: screen.width)
            return NotchLayout(style: .notch, notchRect: notch, closedSize: closed, openSize: open,
                               maxOpenSize: maximum, topInset: 0,
                               panelFrame: panelFrame(midX: notch.midX, size: maximum, topInset: 0, in: screen),
                               config: config)
        }
        let bar = metrics.menuBarHeight > 0 ? metrics.menuBarHeight : 24
        let closed = CGSize(width: config.pillClosedWidth, height: max(bar - 6, 18))
        let open = CGSize(width: min(config.openWidth, screen.width), height: config.openContentHeight + closed.height)
        let inset: CGFloat = 3
        let maximum = maxSize(closed: closed, open: open, band: closed.height, config: config, screenWidth: screen.width)
        return NotchLayout(style: .pill, notchRect: nil, closedSize: closed, openSize: open, maxOpenSize: maximum,
                           topInset: inset,
                           panelFrame: panelFrame(midX: screen.midX, size: maximum, topInset: inset, in: screen),
                           config: config)
    }

    private static func maxSize(closed: CGSize, open: CGSize, band: CGFloat, config: NotchLayoutConfig,
                                screenWidth: CGFloat) -> CGSize {
        CGSize(width: min(max(config.maxOpenWidth, open.width), screenWidth),
               height: max(band + config.maxOpenContentHeight, open.height))
    }

    /// İçeriğin istediği açık boyut, sınırlar içinde: en az kompakt şekil kadar geniş ve bandın
    /// altında biraz yer, en çok `maxOpenSize`. nil ise varsayılan açık boyut.
    public func clampedOpenSize(_ requested: CGSize?) -> CGSize {
        guard let requested else { return openSize }
        let minimumWidth = closedSize.width + 2 * config.compactWingWidth + 40
        return CGSize(width: min(max(requested.width, minimumWidth), maxOpenSize.width),
                      height: min(max(requested.height, bandHeight + 60), maxOpenSize.height))
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
    public func size(for presentation: NotchPresentation, wingWidth: CGFloat? = nil,
                     openSize requested: CGSize? = nil) -> CGSize {
        switch presentation {
        case .closed:
            return closedSize
        case .compact:
            return compactSize(wingWidth)
        case let .peek(compact):
            let base = compact ? compactSize(wingWidth) : closedSize
            return CGSize(width: base.width + config.peekGrowth.width, height: base.height + config.peekGrowth.height)
        case .open:
            return clampedOpenSize(requested)
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
    public func shapeRect(for presentation: NotchPresentation, wingWidth: CGFloat? = nil,
                          openSize requested: CGSize? = nil) -> CGRect {
        let size = size(for: presentation, wingWidth: wingWidth, openSize: requested)
        return CGRect(x: panelFrame.midX - size.width / 2, y: panelFrame.maxY - topInset - size.height,
                      width: size.width, height: size.height)
    }
}
