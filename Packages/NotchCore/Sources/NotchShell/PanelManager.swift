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

    /// Ekran başına gösterim. Seçim yapılmamış ekran `ScreenPolicy`'den varsayılan alır.
    public enum DisplayMode: String, CaseIterable, Sendable {
        /// Ekranın doğal biçimi: çentik varsa çentik, yoksa menü çubuğunda hap.
        case automatic
        /// Menü çubuğunun altında yüzen kart.
        case floating
        case off
    }

    /// Mod çözümü için ekranın yalnız gereken özellikleri; test edilebilir.
    public struct DisplayDescriptor: Equatable, Sendable {
        public var persistentID: String
        public var isBuiltIn: Bool

        public init(persistentID: String, isBuiltIn: Bool) {
            self.persistentID = persistentID
            self.isBuiltIn = isBuiltIn
        }
    }

    /// Ayarlar ekranı için bağlı bir ekranın özeti.
    public struct DisplaySummary: Identifiable, Equatable, Sendable {
        public var id: String { persistentID }
        public var persistentID: String
        public var name: String
        public var hasNotch: Bool
        public var mode: DisplayMode
    }

    /// Çentiksiz ekrandaki hap: her zaman ya da yalnız gösterecek bir etkinlik varken.
    public enum NotchlessVisibility: String, CaseIterable, Sendable {
        case always
        case whenActive

        /// Boştaki yüzey gizlensin mi? Çentik hep görünür; yüzen kart boştayken hep gizlidir
        /// (uygulama içeriğinin üstünde durur). Açıkken (dosya sürükleme konuma gelince de açar)
        /// hiçbiri gizlenmez.
        public func hidesPanel(style: NotchLayout.Style, hasCompactContent: Bool, isOpen: Bool) -> Bool {
            guard !hasCompactContent, !isOpen else { return false }
            switch style {
            case .notch: return false
            case .pill: return self == .whenActive
            case .floating: return true
            }
        }
    }

    /// Kullanıcı seçimi, yoksa politika: "yerleşik ekran" politikasında yerleşik ekran (kapak
    /// kapalıysa ilk ekran) otomatik, diğerleri kapalı; "tüm ekranlar"da hepsi otomatik.
    public nonisolated static func resolveModes(for displays: [DisplayDescriptor], policy: ScreenPolicy,
                                    overrides: [String: DisplayMode]) -> [DisplayMode] {
        let primaryIndex = displays.firstIndex(where: \.isBuiltIn) ?? (displays.isEmpty ? nil : 0)
        return displays.enumerated().map { index, display in
            if let chosen = overrides[display.persistentID] { return chosen }
            switch policy {
            case .allScreens: return .automatic
            case .builtInOrMain: return index == primaryIndex ? .automatic : .off
            }
        }
    }

    /// Öndeki uygulamanın Info.plist kategorisi oyun mu (public.app-category.games, *-games).
    public nonisolated static func isGameCategory(_ category: String?) -> Bool {
        category?.hasPrefix("public.app-category.") == true && category?.hasSuffix("games") == true
    }

    public struct Options: Equatable, Sendable {
        public var screenPolicy: ScreenPolicy = .builtInOrMain
        public var notchlessVisibility: NotchlessVisibility = .always
        public var layout = NotchLayoutConfig()
        public var openDelay: Duration = .milliseconds(150)
        public var hapticsEnabled = true
        public var hideInFullScreen = false
        public var hideFromScreenCapture = false
        public var detectsFileDrags = true
        /// Kalıcı ekran kimliği → mod. Listede olmayan ekran politikadan varsayılan alır.
        public var displayModes: [String: DisplayMode] = [:]
        /// Mission Control ve Exposé'de gizle (pencere "transient"); kapalıyken "stationary".
        public var hideInMissionControl = false
        /// Öndeki uygulama oyunsa tüm ekranlarda gizle.
        public var hideInGames = false

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
    private var gameCategoryCache: [String: Bool] = [:]
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
                let hot = model.currentShapeRect.insetBy(dx: -24, dy: -24)
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
        let wanted = Set(screens.map(\.metrics.displayID))
        var changed = false
        for (id, controller) in controllers where !wanted.contains(id) {
            controller.teardown()
            controllers[id] = nil
            changed = true
        }
        for (metrics, mode) in screens {
            let layout = NotchLayout.make(metrics: metrics, config: options.layout, floating: mode == .floating)
            if let controller = controllers[metrics.displayID] {
                controller.apply(layout: layout, screenName: metrics.name, options: options)
            } else {
                let model = NotchSurfaceModel(layout: layout, displayID: metrics.displayID, screenName: metrics.name)
                let controller = PanelController(model: model, rootView: makeRootView(model))
                model.onOpenChanged = { [weak self, weak controller] _ in
                    self?.updatePointerTracking()
                    controller?.updateVisibility()
                }
                model.onVisibilityInputsChanged = { [weak controller] in controller?.updateVisibility() }
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

    private static func resolvedScreens(_ options: Options) -> [(metrics: ScreenMetrics, mode: DisplayMode)] {
        let all = NSScreen.screens.compactMap(\.metrics)
        let modes = Self.resolveModes(for: all.map { DisplayDescriptor(persistentID: $0.persistentID, isBuiltIn: $0.isBuiltIn) },
                                      policy: options.screenPolicy, overrides: options.displayModes)
        return Array(zip(all, modes))
    }

    private func targetScreens() -> [(metrics: ScreenMetrics, mode: DisplayMode)] {
        Self.resolvedScreens(options).filter { $0.mode != .off }
    }

    /// Bağlı ekranlar ve verilen ayarlarla etkin modları (ayarlar ekranı için).
    public static func displaySummaries(for options: Options) -> [DisplaySummary] {
        resolvedScreens(options).map { metrics, mode in
            DisplaySummary(persistentID: metrics.persistentID, name: metrics.name,
                           hasNotch: metrics.notchRect != nil, mode: mode)
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
        let game = options.hideInGames && isGameFrontmost()
        // İdempotent; yeni kurulan paneller de aynı karardan geçer.
        for (id, controller) in controllers {
            controller.setSuppressed(displays.contains(id) || game)
        }
    }

    /// Kategori uygulama başına bir kez okunur; öndeki uygulama değişince çağrılır, yoklama yok.
    private func isGameFrontmost() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication, let id = app.bundleIdentifier else { return false }
        if let cached = gameCategoryCache[id] { return cached }
        let category = app.bundleURL.flatMap(Bundle.init(url:))?
            .object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
        let isGame = Self.isGameCategory(category)
        gameCategoryCache[id] = isGame
        return isGame
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
    /// Tam ekran ya da oyun nedeniyle bastırıldı.
    private var suppressed = false
    private var notchlessVisibility: PanelManager.NotchlessVisibility = .always

    init(model: NotchSurfaceModel, rootView: AnyView) {
        self.model = model
        panel = NotchPanel(contentRect: model.layout.panelFrame)
        let host = FirstMouseHostingView(rootView: rootView)
        // Barındırma görünümü pencereyi içeriğe göre yeniden boyutlamasın; kare sabit, şekil içinde akar.
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: panel.frame.size)
        host.autoresizingMask = [.width, .height]
        // Dosya bırakma SwiftUI'da değil AppKit'te: dosya sözleri (ekran görüntüsü küçük resmi) yalnız
        // NSFilePromiseReceiver ile alınabiliyor. Katman en üstte ama yalnız sürüklerken isabet alır.
        let container = NSView(frame: host.frame)
        container.autoresizingMask = [.width, .height]
        container.addSubview(host)
        let drop = FileDropView(frame: host.frame)
        drop.autoresizingMask = [.width, .height]
        drop.model = model
        container.addSubview(drop)
        panel.contentView = container
        panel.onScroll = { [weak model] event in model?.scrolled(event) }
        panel.onCancel = { [weak model] in model?.dismiss() }
        model.onKeyboardChanged = { [weak panel] wants in panel?.setTextInput(wants) }
        panel.showImmediately()
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
        // transient: Mission Control/Exposé'de gizlenir; stationary: orada da yerinde kalır (Faz 0 ölçümü).
        let behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle,
                                                     options.hideInMissionControl ? .transient : .stationary]
        if panel.collectionBehavior != behavior {
            panel.collectionBehavior = behavior
            Log.shell.notice("Mission Control: \(options.hideInMissionControl ? "gizlenir (transient)" : "yerinde kalır (stationary)", privacy: .public) (\(screenName, privacy: .public))")
        }
        notchlessVisibility = options.notchlessVisibility
        updateVisibility()
        if !isHidden, !panel.isVisible {
            // boring.notch #336 senaryosu: uyanmadan sonra pencere kaybolursa geri getir.
            Log.shell.notice("panel görünür değildi, öne getirildi (\(screenName, privacy: .public))")
            panel.showImmediately()
        }
    }

    func setSuppressed(_ hidden: Bool) {
        suppressed = hidden
        updateVisibility()
    }

    /// Tam ekranda gizleme ve çentiksiz ekranda boştaki hap. İdempotent.
    func updateVisibility() {
        let idleSurface = notchlessVisibility.hidesPanel(style: model.layout.style,
                                                      hasCompactContent: model.hasCompactContent,
                                                      isOpen: model.isOpen)
        let hidden = suppressed || idleSurface
        guard hidden != isHidden else { return }
        isHidden = hidden
        Log.shell.notice("panel \(hidden ? "gizlendi" : "gösterildi", privacy: .public) (tam ekran/oyun: \(self.suppressed), boşta: \(idleSurface)) (\(self.model.screenName, privacy: .public))")
        // Ani belirip kaybolma yerine saydamlık. Boştaki yüzey gizlenirken önce şekil kapanma
        // animasyonunu bitirir (yoksa küçülme yarıda kesilir); tam ekran/oyunda hemen solar.
        if hidden {
            if suppressed {
                model.dismiss()
                panel.fadeOut()
            } else {
                panel.fadeOut(after: 0.35)
            }
        } else {
            panel.fadeIn()
        }
    }

    func teardown() {
        model.dismiss()
        panel.onScroll = nil
        panel.onCancel = nil
        model.onKeyboardChanged = nil
        panel.orderOut(nil)
    }
}
