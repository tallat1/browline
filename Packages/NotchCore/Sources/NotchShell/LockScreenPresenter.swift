import AppKit
import Observation
import PrivateBridges
import SwiftUI

/// Kilit ekranındaki notch. Ana panellere dokunmaz: kilitlenince ayrı, tıklanamayan bir panel
/// yalnız kompakt durumla SkyLight kilit Space'ine alınır, kilit açılınca çıkarılıp gizlenir.
/// İçeriği uygulama kısıtlar; raf ve takvim gibi kişisel içerik kilitte görünmemeli.
/// Kilit durumu özellik kapalıyken de izlenir (dağıtık bildirim, boşta uyanma yok).
@MainActor
@Observable
public final class LockScreenPresenter {
    public enum Status: Equatable, Sendable {
        case off
        /// SkyLight sembollerinden biri bu macOS'ta yok.
        case unavailable
        case ready
        /// Space kurulamadı ya da pencere eklenemedi.
        case failed
    }

    public private(set) var status: Status = .off
    public private(set) var isLocked = false
    /// Kilit paneli; ilk kilitte kurulur. Uygulama kompakt içeriği buna da bağlar.
    @ObservationIgnored public private(set) var model: NotchSurfaceModel?
    /// Kilitlenince panel gösterilmeden ÖNCE, kilit açılınca panel gizlendikten SONRA çağrılır.
    @ObservationIgnored public var onLockChanged: ((Bool) -> Void)?

    @ObservationIgnored private let makeRootView: (NotchSurfaceModel) -> AnyView
    @ObservationIgnored private var layoutConfig = NotchLayoutConfig()
    @ObservationIgnored private var space: LockScreenSpace?
    @ObservationIgnored private var panel: NotchPanel?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    public init(makeRootView: @escaping (NotchSurfaceModel) -> AnyView) {
        self.makeRootView = makeRootView
    }

    public func start() {
        guard observers.isEmpty else { return }
        let center = DistributedNotificationCenter.default()
        for (name, locked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            observers.append(center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.lockChanged(locked) }
            })
        }
    }

    public func stop() {
        let center = DistributedNotificationCenter.default()
        observers.forEach { center.removeObserver($0) }
        observers.removeAll()
        setEnabled(false)
    }

    /// Açılırken private API'ye yalnız sembol çözümü ve bağlantı kimliği için dokunulur; Space
    /// ilk kilitte kurulur. Kilitliyken açılırsa panel bir sonraki kilitte gelir.
    public func setEnabled(_ enabled: Bool) {
        if enabled {
            guard status == .off else { return }
            space = LockScreenSpace()
            status = space == nil ? .unavailable : .ready
            Log.shell.notice("kilit ekranı: \(self.status == .ready ? "hazır" : "SkyLight sembolleri yok", privacy: .public)")
        } else {
            guard status != .off else { return }
            hidePanel()
            space?.invalidate()
            space = nil
            panel?.contentView = nil
            panel = nil
            model = nil
            status = .off
        }
    }

    public func setLayoutConfig(_ config: NotchLayoutConfig) {
        layoutConfig = config
    }

    #if DEBUG
    /// Yalnız debug: kilit durumunu benzetir. Özellik açıkken reddedilir; SkyLight Space'i kilitsiz
    /// ekranda kurulmasın.
    public func simulateLock(_ locked: Bool) -> Bool {
        guard status != .ready else { return false }
        lockChanged(locked)
        return true
    }
    #endif

    private func lockChanged(_ locked: Bool) {
        guard locked != isLocked else { return }
        Log.shell.notice("ekran \(locked ? "kilitlendi" : "kilidi açıldı", privacy: .public)")
        if locked {
            if status == .ready { prepareModel() }
            isLocked = true
            onLockChanged?(true)
            if status == .ready { showPanel() }
        } else {
            hidePanel()
            isLocked = false
            onLockChanged?(false)
        }
    }

    /// Yerleşik ekran; yoksa menü çubuğunun olduğu ekran.
    private func prepareModel() {
        guard let screen = NSScreen.screens.first(where: \.isBuiltIn) ?? NSScreen.screens.first,
              let metrics = screen.metrics else { return }
        let layout = NotchLayout.make(metrics: metrics, config: layoutConfig)
        if let model, let panel, model.displayID == metrics.displayID {
            model.update(layout: layout, screenName: metrics.name)
            if panel.frame != layout.panelFrame { panel.setFrame(layout.panelFrame, display: false) }
            return
        }
        let model = NotchSurfaceModel(layout: layout, displayID: metrics.displayID, screenName: metrics.name)
        let panel = NotchPanel(contentRect: layout.panelFrame)
        // Ana panelden farkı: her Space'e katılmaz (Space'i SkyLight belirler), olay almaz
        // (kilit ekranındaki parola alanını hiçbir koşulda örtmesin), oturumsuz görünebilir.
        panel.collectionBehavior = [.stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true
        panel.canBecomeVisibleWithoutLogin = true
        let host = NSHostingView(rootView: makeRootView(model))
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: panel.frame.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        self.model = model
        self.panel = panel
    }

    private func showPanel() {
        guard let panel, let space else { return }
        panel.showImmediately()
        if space.attach(windowNumber: panel.windowNumber) {
            Log.shell.notice("kilit ekranı paneli gösterildi")
        } else {
            panel.orderOut(nil)
            status = .failed
            Log.shell.error("kilit ekranı: SkyLight Space kurulamadı, özellik bu oturumda kapalı")
        }
    }

    private func hidePanel() {
        guard let panel else { return }
        space?.detach(windowNumber: panel.windowNumber)
        panel.orderOut(nil)
    }
}
