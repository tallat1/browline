import ActivityAPI
import AppKit
import Integrations
import NotchShell
import SwiftUI

/// Açık notch: tek satır başlık (bantta, çentiğin solunda sekmeler, sağında durum) ve altında sekmenin
/// içeriği. Genişlik tüm sekmelerde aynı (geçişte yana zıplama yok), yalnız boy içeriğe göre değişir.
struct ExpandedView: View {
    let context: NotchContext
    let model: NotchSurfaceModel
    let coordinator: AppCoordinator

    var body: some View {
        let ui = coordinator.ui
        let tabs = coordinator.availableTabs
        let sideWidth = max(0, (context.size.width - context.notchGapWidth) / 2 - context.horizontalInset)
        let bar = TabBarLayout(strip: coordinator.stripTabs, overflow: coordinator.overflowTabs,
                               selected: ui.selectedTab, width: sideWidth)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                TabBar(layout: bar, selected: ui.selectedTab, isMoreOpen: coordinator.ui.isMoreTabsOpen,
                       onHoverIcon: { model.haptic(.detent) },
                       toggleMore: {
                           // Şerit açıkken notch sabit kalsın (imleç kayınca kapanmasın).
                           if !coordinator.ui.isMoreTabsOpen { model.tapped() }
                           coordinator.ui.isMoreTabsOpen.toggle()
                       }) { tab in
                    ui.selectedTab = tab
                    coordinator.ui.isMoreTabsOpen = false
                }
                .frame(width: sideWidth, alignment: .leading)
                Spacer(minLength: context.notchGapWidth)
                StatusArea(coordinator: coordinator).frame(width: sideWidth, alignment: .trailing)
            }
            .frame(height: context.bandHeight)

            if coordinator.ui.isMoreTabsOpen {
                MoreTabsRow(tabs: bar.menu, selected: ui.selectedTab, onHoverChip: { model.haptic(.detent) },
                            edit: {
                                coordinator.ui.isMoreTabsOpen = false
                                coordinator.openSettings?()
                            }) { tab in
                    ui.selectedTab = tab
                    coordinator.ui.isMoreTabsOpen = false
                }
                .padding(.top, NotchDesign.headerSpacing)
                .notchTransition(.listItem)
            }

            // Bekleyen onay sorusu sekmenin önüne geçer; yanıtlanınca sekme geri gelir.
            Group {
                if let question = coordinator.questions.current {
                    QuestionView(question: question, waitingCount: coordinator.questions.questions.count) { decision in
                        AppLog.coordinator.notice("onay sorusu yanıtlandı: \(decision?.rawValue ?? "uygulamaya bırakıldı", privacy: .public)")
                        coordinator.questions.answer(question.id, with: decision)
                    }
                } else {
                    content(ui.selectedTab)
                }
            }
            .padding(.top, NotchDesign.headerSpacing)
            .padding(.bottom, context.bottomInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .id(coordinator.questions.current?.id ?? ui.selectedTab.rawValue)
            .notchTransition(.swap)
        }
        // Sekme hangi yoldan değişirse değişsin (şerit, Diğer menüsü, dosya sürükleme, ayar, debug)
        // içerik ve seçim zemini aynı yayla geçer; şekil boyu kabukta aynı yayla akar.
        .notchAnimation(NotchMotion.resize, value: ui.selectedTab)
        .notchAnimation(NotchMotion.resize, value: coordinator.ui.isMoreTabsOpen)
        .notchAnimation(value: tabs)
        .padding(.horizontal, context.horizontalInset)
        .foregroundStyle(.white)
        .font(NotchDesign.body)
        .onChange(of: model.isFileDragActive, initial: true) { _, dragging in
            if dragging, tabs.contains(.shelf) { ui.selectedTab = .shelf }
        }
        .onChange(of: ui.selectedTab, initial: true) { _, tab in
            model.preferredOpenSize = openSize(for: tab)
        }
        // Sekme hangi yoldan değişirse değişsin (tıklama, şerit, dosya sürükleme) belirgin tık.
        .onChange(of: ui.selectedTab) { _, _ in model.haptic(.selection) }
        .onChange(of: coordinator.questions.current?.id) { _, _ in
            model.preferredOpenSize = openSize(for: ui.selectedTab)
        }
        .onChange(of: coordinator.ui.isMoreTabsOpen) { _, _ in
            model.preferredOpenSize = openSize(for: ui.selectedTab)
        }
        // Notch kapanınca şerit de kapanır; bir dahaki açılış temiz başlasın.
        .onChange(of: model.isOpen) { _, open in
            if !open { coordinator.ui.isMoreTabsOpen = false }
        }
        .notchAnimation(NotchMotion.resize, value: coordinator.questions.current?.id)
    }

    /// İstenen tüm açık boyut: bant + boşluk + içerik (soru varsa soru) + alt boşluk; genişlik sabit.
    private func openSize(for tab: NotchTab) -> CGSize {
        let body = coordinator.questions.current != nil ? QuestionView.height : tab.bodyHeight
        let moreRow = coordinator.ui.isMoreTabsOpen ? NotchDesign.headerSpacing + NotchDesign.Control.regular : 0
        return CGSize(width: NotchDesign.openWidth,
                      height: context.bandHeight + moreRow + NotchDesign.headerSpacing + body + context.bottomInset)
    }

    @ViewBuilder
    private func content(_ tab: NotchTab) -> some View {
        switch tab {
        case .now: NowView(coordinator: coordinator, model: model)
        case .calendar: CalendarTab(calendar: coordinator.calendar,
                                    reminders: coordinator.settings.remindersEnabled ? coordinator.reminders : nil)
        case .shelf: ShelfTab(shelf: coordinator.shelf)
        case .activities: ActivitiesTab(store: coordinator.externalActivities)
        case .notes: NotesTab(notes: coordinator.notes, model: model)
        case .timer: TimerTab(coordinator: coordinator)
        case .system: SystemTab(stats: coordinator.systemStats,
                                bluetooth: coordinator.settings.bluetoothEnabled ? coordinator.bluetooth : nil)
        case .mirror: MirrorTab(mirror: coordinator.mirror)
        case .claude: ClaudeTab(usage: coordinator.claudeUsage)
        case .terminal: TerminalTab(session: coordinator.terminal, model: model)
        case .clipboard: ClipboardTab(history: coordinator.clipboard)
        }
    }
}

extension NotchTab {
    /// İçerik alanının boyu (bant hariç). Genişlik hepsinde `NotchDesign.openWidth`.
    var bodyHeight: CGFloat {
        switch self {
        case .now: 132
        case .calendar: 124
        case .shelf: 104
        case .activities: 120
        case .notes: 196
        case .timer: 84
        case .system: 88
        case .mirror: 300
        case .claude: 150
        // ≈ 77 sütun × 18 satır (12 pt SF Mono).
        case .terminal: 280
        case .clipboard: 200
        }
    }
}

/// Bantta hangi sekme simgelerinin göründüğü. Diğer menüsünden açılan sekme geçici olarak şeride
/// eklenir (nerede olunduğu görünsün); sığmayan sabit sekmeler menüye kayar, seçili olan hep kalır.
struct TabBarLayout: Equatable {
    let shown: [NotchTab]
    let menu: [NotchTab]

    static let slotWidth: CGFloat = NotchDesign.tabIconSize + NotchDesign.tabIconSpacing

    init(strip: [NotchTab], overflow: [NotchTab], selected: NotchTab, width: CGFloat) {
        var shown = strip + (overflow.contains(selected) ? [selected] : [])
        var moved: [NotchTab] = []
        let capacity = max(2, Int((width + NotchDesign.tabIconSpacing) / Self.slotWidth))
        while shown.count + (overflow.isEmpty && moved.isEmpty ? 0 : 1) > capacity,
              let drop = shown.last(where: { $0 != selected && $0 != .now }) {
            shown.removeAll { $0 == drop }
            moved.append(drop)
        }
        self.shown = shown
        let inMenu = Set(overflow + moved)
        menu = NotchTab.allCases.filter { inMenu.contains($0) }
    }
}

/// Sekme simgeleri (yalnız simge; ad üzerine gelince). İnce ağırlık; seçili olan tam beyaz ve zeminli,
/// diğerleri soluk, üzerine gelince aydınlanır. Seçim kayan bir zeminle geçer.
private struct TabBar: View {
    let layout: TabBarLayout
    let selected: NotchTab
    let isMoreOpen: Bool
    let onHoverIcon: () -> Void
    let toggleMore: () -> Void
    let select: (NotchTab) -> Void
    @Namespace private var selection

    var body: some View {
        HStack(spacing: NotchDesign.tabIconSpacing) {
            ForEach(layout.shown) { tab in
                TabIconButton(symbol: tab.symbol, title: tab.title, isSelected: tab == selected,
                              namespace: selection, onHoverEnter: onHoverIcon) { select(tab) }
                    .notchTransition(.fade)
            }
            if !layout.menu.isEmpty {
                TabIconButton(symbol: "ellipsis", title: String(localized: "Diğer sekmeler"), isSelected: isMoreOpen,
                              namespace: nil, onHoverEnter: onHoverIcon, action: toggleMore)
            }
        }
        .notchAnimation(value: layout)
    }
}

private struct TabIconButton: View {
    let symbol: String
    let title: String
    let isSelected: Bool
    /// Kayan seçim zemini için; ••• kendi zeminini çizer.
    let namespace: Namespace.ID?
    /// İmleç simgeye girince (dokunsal çentik).
    let onHoverEnter: () -> Void
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: NotchDesign.Icon.regular, weight: NotchDesign.Icon.weight))
                .frame(width: NotchDesign.tabIconSize, height: NotchDesign.Control.small)
                .foregroundStyle(Color.white.opacity(isSelected ? 1
                                                     : (isHovering ? NotchDesign.hoverIconOpacity : NotchDesign.inactiveIconOpacity)))
                .background { background }
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .onHover { inside in
            if inside, !isHovering { onHoverEnter() }
            isHovering = inside
        }
        .notchAnimation(NotchMotion.hover, value: isHovering)
        .help(title)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: NotchDesign.Radius.small, style: .continuous)
        if isSelected {
            if let namespace {
                shape.fill(NotchDesign.selectionFill).matchedGeometryEffect(id: "selection", in: namespace)
            } else {
                shape.fill(NotchDesign.selectionFill)
            }
        } else if isHovering {
            shape.fill(NotchDesign.cardFill)
        }
    }
}

/// Basılınca hafif küçülme; zemin ve renk görünümün kendisinde.
struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .notchAnimation(NotchMotion.press, value: configuration.isPressed)
    }
}

/// ••• şeridi: sabitlenmemiş sekmeler simge ve adıyla çip olarak; sığmazsa yalnız simge. Yönetim
/// eylemi ("Sekmeleri düzenle…") sağda, ikincil renkte: içerikten ayrı.
private struct MoreTabsRow: View {
    let tabs: [NotchTab]
    let selected: NotchTab
    let onHoverChip: () -> Void
    let edit: () -> Void
    let select: (NotchTab) -> Void

    var body: some View {
        HStack(spacing: NotchDesign.Space.m) {
            ViewThatFits(in: .horizontal) {
                chips(showsTitles: true)
                chips(showsTitles: false)
            }
            Spacer(minLength: NotchDesign.Space.m)
            Button(action: edit) {
                Label("Sekmeleri düzenle…", systemImage: "slider.horizontal.3")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(QuietButtonStyle())
        }
        .frame(height: NotchDesign.Control.regular)
    }

    private func chips(showsTitles: Bool) -> some View {
        HStack(spacing: NotchDesign.Space.xs) {
            ForEach(tabs) { tab in
                TabChip(tab: tab, isSelected: tab == selected, showsTitle: showsTitles, onHoverEnter: onHoverChip) {
                    select(tab)
                }
            }
        }
        .fixedSize()
    }
}

private struct TabChip: View {
    let tab: NotchTab
    let isSelected: Bool
    let showsTitle: Bool
    let onHoverEnter: () -> Void
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: tab.symbol)
                    .font(.system(size: NotchDesign.Icon.small, weight: NotchDesign.Icon.weight))
                if showsTitle {
                    Text(tab.title).font(NotchDesign.captionEmphasized).lineLimit(1)
                }
            }
            .padding(.horizontal, showsTitle ? 10 : 8)
            .frame(height: NotchDesign.Control.small + 2)
            .foregroundStyle(Color.white.opacity(isSelected || isHovering ? 1 : 0.75))
            .background(Capsule().fill(isSelected ? NotchDesign.selectionFill
                                       : (isHovering ? NotchDesign.cardHoverFill : NotchDesign.cardFill)))
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .onHover { inside in
            if inside, !isHovering { onHoverEnter() }
            isHovering = inside
        }
        .notchAnimation(NotchMotion.hover, value: isHovering)
        .help(tab.title)
    }
}

/// Sessiz metin düğmesi: yönetim ve ikincil eylemler. İkincil renkte; üzerine gelince aydınlanır.
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        QuietButtonBody(configuration: configuration)
    }

    private struct QuietButtonBody: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .font(NotchDesign.caption)
                .padding(.horizontal, NotchDesign.Space.s)
                .frame(height: NotchDesign.Control.small)
                .foregroundStyle(Color.white.opacity(isHovering ? 0.95 : 0.6))
                .background(RoundedRectangle(cornerRadius: NotchDesign.Radius.small, style: .continuous)
                    .fill(configuration.isPressed ? NotchDesign.selectionFill : (isHovering ? NotchDesign.cardFill : .clear)))
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : NotchDesign.disabledOpacity)
                .onHover { isHovering = $0 && isEnabled }
                .notchAnimation(NotchMotion.hover, value: isHovering)
        }
    }
}

/// Bantta, çentiğin sağında: hava, uyanık tutma, gizlilik, pil. Sığmadıkça azalır; pil en son gider.
private struct StatusArea: View {
    let coordinator: AppCoordinator

    var body: some View {
        ViewThatFits(in: .horizontal) {
            items(full: true)
            items(full: false)
            Color.clear
        }
        .font(NotchDesign.captionEmphasized)
        .foregroundStyle(.secondary)
    }

    private func items(full: Bool) -> some View {
        HStack(spacing: 10) {
            // Çip belirip kaybolurken (hava gelince, kamera açılınca) ani sıçrama değil solma.
            if full, let conditions = coordinator.weather.conditions, let place = coordinator.weather.place {
                HStack(spacing: 4) {
                    Image(systemName: WeatherMonitor.symbolName(code: conditions.code, isDay: conditions.isDay))
                        .symbolRenderingMode(.multicolor)
                    Text(verbatim: "\(Int(conditions.temperature.rounded()))°").monospacedDigit()
                }
                .help(weatherHelp(place, conditions))
                .notchTransition(.fade)
            }
            if full, coordinator.settings.keepAwakeEnabled {
                KeepAwakeButton(keepAwake: coordinator.keepAwake).notchTransition(.fade)
            }
            // Kamera yeşil, mikrofon turuncu: macOS menü çubuğu göstergeleriyle aynı renkler.
            if coordinator.privacy.isCameraActive {
                Circle().fill(.green).frame(width: 6, height: 6).help("Kamera kullanımda").notchTransition(.fade)
            }
            if coordinator.privacy.isMicrophoneActive {
                Circle().fill(.orange).frame(width: 6, height: 6).help("Mikrofon kullanımda").notchTransition(.fade)
            }
            if coordinator.settings.batteryEnabled, let state = coordinator.battery.state {
                HStack(spacing: 4) {
                    Text("%\(state.percent)").monospacedDigit().contentTransition(.numericText())
                    Image(systemName: state.symbolName)
                        .foregroundStyle(state.isCharging ? .green : (state.percent <= 20 ? .red : .white))
                }
            }
        }
        .fixedSize()
        .notchAnimation(value: StatusSignature(coordinator: coordinator))
    }
}

/// Durum çiplerinden hangilerinin göründüğü; değişince çipler solarak girip çıkar.
private struct StatusSignature: Equatable {
    let weather: Bool, keepAwake: Bool, camera: Bool, microphone: Bool, battery: Int?

    @MainActor
    init(coordinator: AppCoordinator) {
        weather = coordinator.weather.conditions != nil
        keepAwake = coordinator.keepAwake.isActive
        camera = coordinator.privacy.isCameraActive
        microphone = coordinator.privacy.isMicrophoneActive
        battery = coordinator.battery.state?.percent
    }
}

private struct KeepAwakeButton: View {
    let keepAwake: KeepAwake

    var body: some View {
        Button {
            if keepAwake.isActive { keepAwake.stop() } else { keepAwake.start(reason: String(localized: "NotchMVP: uyanık tut")) }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: keepAwake.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                // Süreli açıksa kalan süre (menü çubuğundan 30 dk / 1 sa / 2 sa); başka yerde görünmüyordu.
                if let endsAt = keepAwake.endsAt {
                    TimelineView(.everyMinute) { timeline in
                        Text("\(Int((max(0, endsAt.timeIntervalSince(timeline.currentDate)) / 60).rounded(.up))) dk")
                            .monospacedDigit()
                    }
                }
            }
            .foregroundStyle(keepAwake.isActive ? .orange : .secondary)
            .padding(.horizontal, keepAwake.endsAt == nil ? 0 : 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .help(keepAwake.isActive ? String(localized: "Uyanık tutmayı kapat") : String(localized: "Ekranı uyanık tut"))
    }
}

private func weatherHelp(_ place: WeatherMonitor.Place, _ conditions: WeatherMonitor.Conditions) -> String {
    guard let high = conditions.high, let low = conditions.low else { return place.name }
    return place.name + " · " + String(localized: "en düşük \(Int(low.rounded()))°, en yüksek \(Int(high.rounded()))°")
}

extension BatteryMonitor.State {
    var symbolName: String {
        if isCharging { return "battery.100.bolt" }
        switch percent {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }
}
