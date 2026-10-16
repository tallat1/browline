import AppKit
import Observation

/// Ekran başına notch durumu. Gecikmeler iptal edilebilir Task ile; sürekli çalışan zamanlayıcı yok.
@MainActor
@Observable
public final class NotchSurfaceModel {
    public private(set) var layout: NotchLayout
    public let displayID: CGDirectDisplayID
    public private(set) var screenName: String

    public private(set) var isOpen = false
    public private(set) var isPeeking = false
    /// Tıklamayla açılan notch imleç ayrılınca kapanmaz; dışarı tıklama ya da Esc kapatır.
    public private(set) var isPinned = false
    /// Notch üzerine dosya sürükleniyor; uygulama bunu rafı öne almak için kullanır.
    public private(set) var isFileDragActive = false
    /// Uygulamanın kompakt içeriği varsa (çalan müzik, yaklaşan toplantı) kapalı şekil kanatlanır.
    public var hasCompactContent = false {
        didSet { if hasCompactContent != oldValue { onVisibilityInputsChanged?() } }
    }
    /// Kompakt kanat genişliği; nil ise dar kanat. Başlık taşıyan etkinlikler için genişletilir.
    public var compactWingWidth: CGFloat?
    /// İçeriğin istediği açık boyut (sekmeye göre); nil ise yerleşimin varsayılanı. Değişince şekil
    /// yay animasyonuyla büyür ya da küçülür; panel karesi değişmez.
    public var preferredOpenSize: CGSize?
    public private(set) var hapticTick = 0

    @ObservationIgnored public var openDelay: Duration = .milliseconds(150)
    @ObservationIgnored public var hapticsEnabled = true
    @ObservationIgnored private var lastHapticAt = Date.distantPast
    /// Art arda tıklar arasında en az bu kadar: imleç simgeler üzerinde hızla kayınca titreşim olmasın.
    static let hapticMinimumInterval: TimeInterval = 0.04

    public enum Haptic: String, Sendable {
        /// Sekme simgesinin üzerine gelme: hafif çentik.
        case detent
        /// Sekme seçimi: belirgin tık.
        case selection
    }
    /// Açık/kapalı geçişinde yönetici imleç izleyicilerini kurar ya da kaldırır.
    @ObservationIgnored var onOpenChanged: ((Bool) -> Void)?
    /// Çentiksiz ekranda "yalnız etkinlik varken" görünürlüğü bu değişikliklere bağlı.
    @ObservationIgnored var onVisibilityInputsChanged: (() -> Void)?
    /// Açık görünümdeki bir metin alanı yazmaya hazır: panel yalnız bu sürede key olabilir. Ekranda
    /// görünmesi yetmez, kullanıcı alana tıklayınca key olur (hover klavyeyi çalmasın). Kapanınca düşer.
    public var wantsKeyboard = false {
        didSet { if wantsKeyboard != oldValue { onKeyboardChanged?(wantsKeyboard) } }
    }
    @ObservationIgnored var onKeyboardChanged: ((Bool) -> Void)?

    /// Açıkken yatay kaydırma; true ileri. Uygulama bağlar.
    @ObservationIgnored public var onHorizontalSwipe: ((_ forward: Bool) -> Void)?
    /// Açık notch'a dosya bırakıldı (adres, dosya sözü ya da görsel); uygulama `FileDrop.receive` ile
    /// alır. Kabul ettiyse true. Atanmamışsa bırakma reddedilir.
    @ObservationIgnored public var onFileDrop: ((NSPasteboard) -> Bool)?
    /// Bırakılabilir bir şey notch'un üstünde (raf çerçevesi aydınlanır).
    public internal(set) var isDropTargeted = false

    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    @ObservationIgnored private var isPointerInside = false
    @ObservationIgnored private var scrollHandledInGesture = false
    /// Fare tekerleği aşamasız gelir; tık başına bir eylem, art arda tıklar birleşir.
    @ObservationIgnored private var lastWheelAction = Date.distantPast
    static let wheelActionInterval: TimeInterval = 0.35
    /// İmleç konumu (global); testler sabit bir nokta verir.
    @ObservationIgnored var pointerLocation: () -> CGPoint = { NSEvent.mouseLocation }

    init(layout: NotchLayout, displayID: CGDirectDisplayID, screenName: String) {
        self.layout = layout
        self.displayID = displayID
        self.screenName = screenName
    }

    public var presentation: NotchPresentation {
        if isOpen { return .open }
        if isPeeking { return .peek(compact: hasCompactContent) }
        return hasCompactContent ? .compact : .closed
    }

    /// Şu anki görünür şekil, global koordinatta.
    public var currentShapeRect: CGRect {
        layout.shapeRect(for: presentation, wingWidth: compactWingWidth, openSize: preferredOpenSize)
    }

    private var openShapeRect: CGRect {
        layout.shapeRect(for: .open, openSize: preferredOpenSize)
    }

    func update(layout: NotchLayout, screenName: String) {
        if layout != self.layout { self.layout = layout }
        if screenName != self.screenName { self.screenName = screenName }
    }

    // MARK: - Girdi

    /// SwiftUI .onHover ve açıkken imleç izleyicisi buraya gelir.
    public func hoverChanged(_ inside: Bool) {
        guard inside != isPointerInside else { return }
        Log.shell.info("hover \(inside ? "giriş" : "çıkış", privacy: .public) (\(self.screenName, privacy: .public))")
        isPointerInside = inside
        hoverTask?.cancel()
        if inside {
            guard !isOpen else { return }
            isPeeking = true
            let delay = openDelay
            hoverTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: delay)
                guard let self, !Task.isCancelled, self.isPointerInside else { return }
                self.setOpen(true)
            }
        } else {
            isPeeking = false
            guard isOpen, !isPinned, !isFileDragActive else { return }
            hoverTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(120))
                guard let self, !Task.isCancelled, !self.isPointerInside, !self.isPinned,
                      !self.isFileDragActive else { return }
                self.setOpen(false)
            }
        }
    }

    /// Şekle tıklama: kapalıysa gecikme beklemeden açar ve sabitler; açıksa sabitler.
    public func tapped() {
        hoverTask?.cancel()
        isPinned = true
        setOpen(true)
    }

    /// Sekmeler arasında gezinirken dokunsal geri bildirim (Force Touch trackpad'de, parmak yüzeydeyken
    /// hissedilir). Ayar kapalıysa yok.
    public func haptic(_ kind: Haptic) {
        guard hapticsEnabled, Date.now.timeIntervalSince(lastHapticAt) > Self.hapticMinimumInterval else { return }
        lastHapticAt = .now
        NSHapticFeedbackManager.defaultPerformer.perform(kind == .selection ? .levelChange : .alignment,
                                                         performanceTime: .now)
        Log.shell.debug("dokunsal: \(kind.rawValue, privacy: .public)")
    }

    /// Esc ya da dışarı tıklama.
    public func dismiss() {
        hoverTask?.cancel()
        isPinned = false
        isPeeking = false
        setOpen(false)
    }

    /// İki parmakla (ya da tekerlekle) aşağı kaydırma açar ve sabitler, yukarı kaydırma kapatır.
    /// Jest başına bir kez. Açıkken dikey kaydırma içeriğe aittir (not, terminal, liste): yalnız bant
    /// (sekme/durum satırı) üzerindeyken kapatır. Eskiden içerikte yukarı kaydırmak notch'u kapatıyordu.
    func scrolled(_ event: NSEvent) {
        // Atalet (parmak kalktıktan sonra süren kaydırma) jest değil: yatayda ikinci parça geçişi ya da
        // dikeyde ikinci aç/kapa olmasın.
        guard event.momentumPhase.isEmpty else { return }
        let isWheel = event.phase.isEmpty
        if isWheel {
            guard Date.now.timeIntervalSince(lastWheelAction) > Self.wheelActionInterval else { return }
        } else {
            if event.phase.contains(.began) || event.phase.contains(.mayBegin) { scrollHandledInGesture = false }
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) { scrollHandledInGesture = false; return }
            guard !scrollHandledInGesture else { return }
        }
        // Açıkken yatay kaydırma: uygulama karar verir (Şimdi sekmesinde parça geçişi).
        if isOpen, let forward = Self.horizontalSwipe(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY,
                                                       inverted: event.isDirectionInvertedFromDevice) {
            markScrollHandled(isWheel: isWheel)
            onHorizontalSwipe?(forward)
            return
        }
        guard abs(event.scrollingDeltaY) > (isWheel ? 0.5 : 4) else { return }
        if isOpen, !isPointerOverBand { return }
        // Doğal kaydırmada içerik parmakla aynı yöne gider; deltaY işareti buna göre çevrilir.
        let fingersDown = event.isDirectionInvertedFromDevice ? event.scrollingDeltaY > 0 : event.scrollingDeltaY < 0
        markScrollHandled(isWheel: isWheel)
        if fingersDown { tapped() } else if isOpen { dismiss() }
    }

    private func markScrollHandled(isWheel: Bool) {
        if isWheel { lastWheelAction = .now } else { scrollHandledInGesture = true }
    }

    /// İmleç açık şeklin üst bandında mı (sekmeler ve durum satırı).
    private var isPointerOverBand: Bool {
        let rect = openShapeRect
        let band = CGRect(x: rect.minX, y: rect.maxY - layout.bandHeight, width: rect.width, height: layout.bandHeight)
        return band.contains(pointerLocation())
    }

    /// Yatay ağırlıklı iki parmak kaydırması: parmaklar sola → ileri (true), sağa → geri.
    /// Dikey ağırlıklıysa ya da eşik altındaysa nil. Doğal kaydırmada işaret ters gelir.
    public nonisolated static func horizontalSwipe(deltaX: CGFloat, deltaY: CGFloat, inverted: Bool) -> Bool? {
        guard abs(deltaX) > 6, abs(deltaX) > abs(deltaY) * 1.5 else { return nil }
        let fingersLeft = inverted ? deltaX < 0 : deltaX > 0
        return fingersLeft
    }

    /// Açıkken global/local imleç izleyicisi. SwiftUI hover çıkışı kaçarsa (Faz 0'da bir kez
    /// 106 sn açık kalma gözlendi) kapanmayı bu sağlar.
    func pointerMoved(to point: CGPoint) {
        guard isOpen else { return }
        let inside = openShapeRect.insetBy(dx: -10, dy: -10).contains(point)
        if inside != isPointerInside { hoverChanged(inside) }
    }

    /// Açıkken şeklin dışına yapılan tıklama.
    func clickedOutside(at point: CGPoint) {
        guard isOpen, !openShapeRect.contains(point) else { return }
        dismiss()
    }

    func fileDragChanged(active: Bool, overNotch: Bool) {
        if active, overNotch, !isFileDragActive {
            isFileDragActive = true
            hoverTask?.cancel()
            setOpen(true)
        } else if !active, isFileDragActive {
            isFileDragActive = false
            if !isPointerInside, !isPinned { setOpen(false) }
        }
    }

    // MARK: - Durum

    private func setOpen(_ open: Bool) {
        if open { isPeeking = false }
        if !open {
            isPinned = false
            wantsKeyboard = false
        }
        guard open != isOpen else { return }
        if open, hapticsEnabled { hapticTick &+= 1 }
        isOpen = open
        Log.shell.info("notch \(open ? "açıldı" : "kapandı", privacy: .public) (\(self.screenName, privacy: .public))")
        onOpenChanged?(open)
    }
}
