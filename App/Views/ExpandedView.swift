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
                TabBar(layout: bar, selected: ui.selectedTab, onMenuOpen: { model.tapped() },
                       onEditTabs: { coordinator.openSettings?() }) { tab in
                    ui.selectedTab = tab
                }
                .frame(width: sideWidth, alignment: .leading)
                Spacer(minLength: context.notchGapWidth)
                StatusArea(coordinator: coordinator).frame(width: sideWidth, alignment: .trailing)
            }
            .frame(height: context.bandHeight)

            content(ui.selectedTab)
                .padding(.top, NotchDesign.headerSpacing)
                .padding(.bottom, context.bottomInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .id(ui.selectedTab)
                .notchTransition(.swap)
        }
        // Sekme hangi yoldan değişirse değişsin (şerit, Diğer menüsü, dosya sürükleme, ayar, debug)
        // içerik ve seçim zemini aynı yayla geçer; şekil boyu kabukta aynı yayla akar.
        .notchAnimation(NotchMotion.resize, value: ui.selectedTab)
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
    }

    /// Sekmenin istediği tüm açık boyut: bant + boşluk + içerik + alt boşluk; genişlik sabit.
    private func openSize(for tab: NotchTab) -> CGSize {
        CGSize(width: NotchDesign.openWidth,
               height: context.bandHeight + NotchDesign.headerSpacing + tab.bodyHeight + context.bottomInset)
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
        case .system: SystemTab(stats: coordinator.systemStats)
        case .mirror: MirrorTab(mirror: coordinator.mirror)
        case .claude: ClaudeTab(usage: coordinator.claudeUsage)
        case .terminal: TerminalTab(session: coordinator.terminal, model: model)
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

/// Sekme simgeleri (yalnız simge; ad üzerine gelince). Seçim kayan bir zeminle geçer.
private struct TabBar: View {
    let layout: TabBarLayout
    let selected: NotchTab
    let onMenuOpen: () -> Void
    let onEditTabs: () -> Void
    let select: (NotchTab) -> Void
    @Namespace private var selection

    var body: some View {
        HStack(spacing: NotchDesign.tabIconSpacing) {
            ForEach(layout.shown) { tab in
                TabIconButton(tab: tab, isSelected: tab == selected, namespace: selection) { select(tab) }
                    .notchTransition(.fade)
            }
            if !layout.menu.isEmpty {
                MoreTabsButton(tabs: layout.menu, selected: selected, onOpen: onMenuOpen, onEdit: onEditTabs,
                               select: select)
            }
        }
        .notchAnimation(value: layout)
    }
}

private struct TabIconButton: View {
    let tab: NotchTab
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: tab.symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: NotchDesign.tabIconSize, height: NotchDesign.tabIconSize)
                .foregroundStyle(isSelected ? Color.white : Color.white.opacity(isHovering ? 0.85 : 0.5))
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 7, style: .continuous).fill(NotchDesign.selectionFill)
                            .matchedGeometryEffect(id: "selection", in: namespace)
                    } else if isHovering {
                        RoundedRectangle(cornerRadius: 7, style: .continuous).fill(NotchDesign.cardFill)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .notchAnimation(NotchMotion.hover, value: isHovering)
        .help(tab.title)
        .accessibilityLabel(tab.title)
    }
}

/// "•••": sabitlenmemiş sekmeler. Menü imlecin olduğu yerde açılır; açıkken notch sabitlenir.
private struct MoreTabsButton: View {
    let tabs: [NotchTab]
    let selected: NotchTab
    let onOpen: () -> Void
    let onEdit: () -> Void
    let select: (NotchTab) -> Void
    @State private var isHovering = false

    var body: some View {
        Button {
            onOpen()
            TabMenu.show(tabs: tabs, selected: selected, select: select, edit: onEdit)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: NotchDesign.tabIconSize, height: NotchDesign.tabIconSize)
                .foregroundStyle(Color.white.opacity(isHovering ? 0.85 : 0.5))
                .background {
                    if isHovering {
                        RoundedRectangle(cornerRadius: 7, style: .continuous).fill(NotchDesign.cardFill)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .notchAnimation(NotchMotion.hover, value: isHovering)
        .help("Diğer sekmeler")
        .accessibilityLabel("Diğer sekmeler")
    }
}

@MainActor
private enum TabMenu {
    static func show(tabs: [NotchTab], selected: NotchTab, select: @escaping (NotchTab) -> Void,
                     edit: @escaping () -> Void) {
        AppLog.coordinator.notice("sekmeler: Diğer menüsü açıldı (\(tabs.count))")
        let menu = NSMenu()
        for tab in tabs {
            let item = NSMenuItem(title: tab.title, action: #selector(MenuTarget.run), keyEquivalent: "")
            let target = MenuTarget { select(tab) }
            item.target = target
            item.representedObject = target
            item.state = tab == selected ? .on : .off
            item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: nil)
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let editItem = NSMenuItem(title: String(localized: "Sekmeleri düzenle…"), action: #selector(MenuTarget.run),
                                  keyEquivalent: "")
        let editTarget = MenuTarget(edit)
        editItem.target = editTarget
        editItem.representedObject = editTarget
        menu.addItem(editItem)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    final class MenuTarget: NSObject {
        let handler: () -> Void
        init(_ handler: @escaping () -> Void) { self.handler = handler }
        @objc func run() { handler() }
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
            Image(systemName: keepAwake.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                .foregroundStyle(keepAwake.isActive ? .orange : .secondary)
        }
        .buttonStyle(IconButtonStyle(size: 22))
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
