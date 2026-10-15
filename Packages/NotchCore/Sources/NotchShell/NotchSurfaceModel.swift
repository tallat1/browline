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
    public var hasCompactContent = false
    /// Kompakt kanat genişliği; nil ise dar kanat. Başlık taşıyan etkinlikler için genişletilir.
    public var compactWingWidth: CGFloat?
    public private(set) var hapticTick = 0

    @ObservationIgnored public var openDelay: Duration = .milliseconds(150)
    @ObservationIgnored public var hapticsEnabled = true
    /// Açık/kapalı geçişinde yönetici imleç izleyicilerini kurar ya da kaldırır.
    @ObservationIgnored var onOpenChanged: ((Bool) -> Void)?

    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    @ObservationIgnored private var isPointerInside = false
    @ObservationIgnored private var scrollHandledInGesture = false

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
        layout.shapeRect(for: presentation, wingWidth: compactWingWidth)
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

    /// Esc ya da dışarı tıklama.
    public func dismiss() {
        hoverTask?.cancel()
        isPinned = false
        isPeeking = false
        setOpen(false)
    }

    /// İki parmakla aşağı kaydırma açar ve sabitler, yukarı kaydırma kapatır. Jest başına bir kez.
    func scrolled(_ event: NSEvent) {
        if event.phase == .began || event.phase == .mayBegin { scrollHandledInGesture = false }
        if event.phase == .ended || event.phase == .cancelled { scrollHandledInGesture = false; return }
        guard !scrollHandledInGesture, abs(event.scrollingDeltaY) > 4 else { return }
        // Doğal kaydırmada içerik parmakla aynı yöne gider; deltaY işareti buna göre çevrilir.
        let fingersDown = event.isDirectionInvertedFromDevice ? event.scrollingDeltaY > 0 : event.scrollingDeltaY < 0
        scrollHandledInGesture = true
        if fingersDown { tapped() } else if isOpen { dismiss() }
    }

    /// Açıkken global/local imleç izleyicisi. SwiftUI hover çıkışı kaçarsa (Faz 0'da bir kez
    /// 106 sn açık kalma gözlendi) kapanmayı bu sağlar.
    func pointerMoved(to point: CGPoint) {
        guard isOpen else { return }
        let inside = layout.shapeRect(for: .open).insetBy(dx: -10, dy: -10).contains(point)
        if inside != isPointerInside { hoverChanged(inside) }
    }

    /// Açıkken şeklin dışına yapılan tıklama.
    func clickedOutside(at point: CGPoint) {
        guard isOpen, !layout.shapeRect(for: .open).contains(point) else { return }
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
        if !open { isPinned = false }
        guard open != isOpen else { return }
        if open, hapticsEnabled { hapticTick &+= 1 }
        isOpen = open
        Log.shell.info("notch \(open ? "açıldı" : "kapandı", privacy: .public) (\(self.screenName, privacy: .public))")
        onOpenChanged?(open)
    }
}
