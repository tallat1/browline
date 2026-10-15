import AppKit
import SwiftUI

/// İlk tıklamayı "pencereyi etkinleştir" diye yutmasın; düğmeler tek tıkla çalışsın.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Ekran başına bir panel. Ekran parametreleri değişince ve uyanınca idempotent yeniden kurulum.
@MainActor
public final class PanelManager {
    public enum ScreenPolicy: String, CaseIterable, Sendable {
        /// Yerleşik ekran; kapak kapalıysa menü çubuğunun olduğu ekran.
        case builtInOrMain
        /// Her ekran; çentiksiz ekranda hap.
        case allScreens
    }

    public struct Options: Equatable, Sendable {
        public var screenPolicy: ScreenPolicy = .builtInOrMain
        public var layout = NotchLayoutConfig()
        public var openDelay: Duration = .milliseconds(150)
        public var hapticsEnabled = true
        public var hideInFullScreen = false
        public var hideFromScreenCapture = false
        public var detectsFileDrags = true

        public init() {}
    }

    public var options: Options {
        didSet {
            guard options != oldValue else { return }
            rebuild(trigger: "ayarlar")
        }
    }

    /// Model kurulunca ya da kaldırılınca uygulama kompakt içeriği bağlar.
    public var onModelsChanged: (([NotchSurfaceModel]) -> Void)?
    public var models: [NotchSurfaceModel] { controllers.values.map(\.model) }

    private let makeRootView: (NotchSurfaceModel) -> AnyView
    private var controllers: [CGDirectDisplayID: PanelController] = [:]
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private let pointerHub = PointerHub()

    public init(options: Options = .init(), makeRootView: @escaping (NotchSurfaceModel) -> AnyView) {
        self.options = options
        self.makeRootView = makeRootView
    }

    public func start() {
        pointerHub.onPointerMoved = { [weak self] point in
            self?.controllers.values.forEach { $0.model.pointerMoved(to: point) }
        }
        pointerHub.onMouseDown = { [weak self] point in
            self?.controllers.values.forEach { $0.model.clickedOutside(at: point) }
        }
        pointerHub.onFileDrag = { [weak self] active, point in
            guard let self else { return }
            for model in self.models {
                let hot = model.layout.shapeRect(for: model.presentation).insetBy(dx: -24, dy: -24)
                model.fileDragChanged(active: active, overNotch: hot.contains(point))
            }
        }

        let center = NotificationCenter.default
        observe(center, NSApplication.didChangeScreenParametersNotification) { $0.rebuild(trigger: "ekran parametreleri") }
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.didWakeNotification) { manager in
            manager.rebuild(trigger: "uyanma")
            // Uyanmada ekran parametreleri geç gelebiliyor; tek seferlik ikinci deneme.
            Task { @MainActor [weak manager] in
                try? await Task.sleep(for: .seconds(1.5))
                manager?.rebuild(trigger: "uyanma +1,5 sn")
            }
        }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.rebuild(trigger: "ekran uyanması") }
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { $0.refreshFullScreenState() }
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { $0.refreshFullScreenState() }
        rebuild(trigger: "açılış")
    }

    public func stop() {
        observers.forEach { center, token in center.removeObserver(token) }
        observers.removeAll()
        pointerHub.setTracking(false)
        pointerHub.setDragDetection(false)
        controllers.values.forEach { $0.teardown() }
        controllers.removeAll()
    }

    /// İdempotent: aynı ekranlar ve ayarlarla çağrılınca hiçbir şey değiştirmez.
    public func rebuild(trigger: String) {
        let screens = targetScreens()
        let wanted = Set(screens.compactMap(\.displayID))
        var changed = false
        for (id, controller) in controllers where !wanted.contains(id) {
            controller.teardown()
            controllers[id] = nil
            changed = true
        }
        for screen in screens {
            guard let metrics = screen.metrics else { continue }
            let layout = NotchLayout.make(metrics: metrics, config: options.layout)
            if let controller = controllers[metrics.displayID] {
                controller.apply(layout: layout, screenName: metrics.name, options: options)
            } else {
                let model = NotchSurfaceModel(layout: layout, displayID: metrics.displayID, screenName: metrics.name)
                model.onOpenChanged = { [weak self] _ in self?.updatePointerTracking() }
                let controller = PanelController(model: model, rootView: makeRootView(model))
                controller.apply(layout: layout, screenName: metrics.name, options: options)
                controllers[metrics.displayID] = controller
                changed = true
            }
        }
        pointerHub.setDragDetection(options.detectsFileDrags && !controllers.isEmpty)
        refreshFullScreenState()
        if changed { onModelsChanged?(models) }
        Log.shell.info("panel yeniden kurulumu (\(trigger, privacy: .public)): \(self.controllers.count) ekran")
    }

    private func targetScreens() -> [NSScreen] {
        switch options.screenPolicy {
        case .allScreens:
            return NSScreen.screens
        case .builtInOrMain:
            if let builtIn = NSScreen.screens.first(where: \.isBuiltIn) { return [builtIn] }
            return NSScreen.screens.first.map { [$0] } ?? []
        }
    }

    private func updatePointerTracking() {
        pointerHub.setTracking(controllers.values.contains { $0.model.isOpen })
    }

    /// Tam ekran sezgisi: öndeki uygulamanın katman 0'da bir ekranın tam genişliğini ve en az
    /// %90 yüksekliğini kaplayan penceresi var mı. Faz 0'da Safari, QuickTime ve Chrome videosunda
    /// doğrulandı. Private API kullanmaz; pencere adı okumadığı için Ekran Kaydı izni istemez.
    private func refreshFullScreenState() {
        let displays = options.hideInFullScreen ? Self.fullScreenDisplays() : []
        // setHidden idempotent; yeni kurulan paneller de aynı karardan geçer.
        for (id, controller) in controllers {
            controller.setHidden(displays.contains(id))
        }
    }

    private static func fullScreenDisplays() -> Set<CGDirectDisplayID> {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let primary = NSScreen.screens.first else { return [] }
        // CGWindowList üst-sol kökenli; NSScreen alt-sol. Ekranlar CG koordinatına çevrilir.
        let screens: [(CGDirectDisplayID, CGRect)] = NSScreen.screens.compactMap { screen in
            guard let id = screen.displayID else { return nil }
            return (id, CGRect(x: screen.frame.minX, y: primary.frame.maxY - screen.frame.maxY,
                               width: screen.frame.width, height: screen.frame.height))
        }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                 kCGNullWindowID) as? [[String: Any]] ?? []
        var result: Set<CGDirectDisplayID> = []
        for window in windows {
            guard window[kCGWindowOwnerPID as String] as? pid_t == pid,
                  window[kCGWindowLayer as String] as? Int == 0,
                  let dictionary = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dictionary) else { continue }
            for (id, rect) in screens where bounds.minX == rect.minX && bounds.width == rect.width
                && bounds.maxY == rect.maxY && bounds.height >= rect.height * 0.9 {
                result.insert(id)
            }
        }
        return result
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         _ handler: @escaping @MainActor (PanelManager) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                handler(self)
            }
        }
        observers.append((center, token))
    }
}

/// Tek bir ekranın paneli. apply() idempotent.
@MainActor
private final class PanelController {
    let model: NotchSurfaceModel
    private let panel: NotchPanel
    private var isHidden = false

    init(model: NotchSurfaceModel, rootView: AnyView) {
        self.model = model
        panel = NotchPanel(contentRect: model.layout.panelFrame)
        let host = FirstMouseHostingView(rootView: rootView)
        // Barındırma görünümü pencereyi içeriğe göre yeniden boyutlamasın; kare sabit, şekil içinde akar.
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: panel.frame.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.onScroll = { [weak model] event in model?.scrolled(event) }
        panel.onCancel = { [weak model] in model?.dismiss() }
        panel.orderFrontRegardless()
    }

    func apply(layout: NotchLayout, screenName: String, options: PanelManager.Options) {
        model.update(layout: layout, screenName: screenName)
        model.openDelay = options.openDelay
        model.hapticsEnabled = options.hapticsEnabled
        if panel.frame != layout.panelFrame {
            panel.setFrame(layout.panelFrame, display: false)
        }
        let sharing: NSWindow.SharingType = options.hideFromScreenCapture ? .none : .readOnly
        if panel.sharingType != sharing { panel.sharingType = sharing }
        if !isHidden, !panel.isVisible {
            // boring.notch #336 senaryosu: uyanmadan sonra pencere kaybolursa geri getir.
            Log.shell.notice("panel görünür değildi, öne getirildi (\(screenName, privacy: .public))")
            panel.orderFrontRegardless()
        }
    }

    func setHidden(_ hidden: Bool) {
        guard hidden != isHidden else { return }
        isHidden = hidden
        if hidden {
            model.dismiss()
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    func teardown() {
        model.dismiss()
        panel.onScroll = nil
        panel.onCancel = nil
        panel.orderOut(nil)
    }
}
