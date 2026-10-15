import Integrations
import NotchShell
import SwiftUI

/// Açık notch: bantta (çentiğin iki yanı) solda bulunulan sekmenin adı, sağda durum; altında
/// sekme şeridi; en altta sekmenin içeriği. Her sekme kendi boyunu ister, şekil ona göre açılır.
struct ExpandedView: View {
    let context: NotchContext
    let model: NotchSurfaceModel
    let coordinator: AppCoordinator

    var body: some View {
        let ui = coordinator.ui
        let tabs = coordinator.availableTabs
        let sideWidth = max(0, (context.size.width - context.notchGapWidth) / 2 - context.horizontalInset)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if tabs.contains(ui.selectedTab) {
                    SectionTitle(tab: ui.selectedTab).frame(width: sideWidth, alignment: .leading)
                } else {
                    Color.clear.frame(width: sideWidth)
                }
                Spacer(minLength: context.notchGapWidth)
                StatusArea(coordinator: coordinator).frame(width: sideWidth, alignment: .trailing)
            }
            .frame(height: context.bandHeight)

            if tabs.isEmpty {
                EmptyStateView(symbol: "square.grid.2x2", title: "Tüm modüller kapalı",
                               message: "Menü çubuğundaki simgeden Ayarlar'ı açın.")
            } else {
                TabStrip(tabs: tabs, selected: ui.selectedTab,
                         availableWidth: context.size.width - 2 * context.horizontalInset) { tab in
                    ui.selectedTab = tab
                }
                .frame(height: NotchDesign.stripHeight)
                .padding(.top, 4)

                content(ui.selectedTab)
                    .padding(.top, NotchDesign.stripSpacing)
                    .padding(.bottom, context.bottomInset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .id(ui.selectedTab)
                    .notchTransition(.swap)
            }
        }
        // Sekme hangi yoldan değişirse değişsin (şerit, dosya sürükleme, ayar, debug) içerik ve seçim
        // zemini aynı yayla geçer; şekil boyu kabukta aynı yayla akar. Eskiden yalnız şerit düğmesi canlıydı.
        .notchAnimation(NotchMotion.resize, value: ui.selectedTab)
        .notchAnimation(value: tabs)
        .padding(.horizontal, context.horizontalInset)
        .foregroundStyle(.white)
        .font(NotchDesign.body)
        .onChange(of: model.isFileDragActive, initial: true) { _, dragging in
            if dragging, tabs.contains(.shelf) { ui.selectedTab = .shelf }
        }
        .onChange(of: ui.selectedTab, initial: true) { _, tab in
            model.preferredOpenSize = tabs.isEmpty ? nil : openSize(for: tab)
        }
    }

    /// Sekmenin istediği tüm açık boyut: bant + şerit + içerik + alt boşluk.
    private func openSize(for tab: NotchTab) -> CGSize {
        let body = tab.bodySize
        return CGSize(width: body.width,
                      height: context.bandHeight + 4 + NotchDesign.stripHeight + NotchDesign.stripSpacing
                        + body.height + context.bottomInset)
    }

    @ViewBuilder
    private func content(_ tab: NotchTab) -> some View {
        switch tab {
        case .media: MediaTab(nowPlaying: coordinator.nowPlaying, volume: coordinator.volume, model: model,
                              sourceDescription: coordinator.nowPlayingSourceDescription)
        case .calendar: CalendarTab(calendar: coordinator.calendar,
                                    reminders: coordinator.settings.remindersEnabled ? coordinator.reminders : nil)
        case .shelf: ShelfTab(shelf: coordinator.shelf)
        case .activities: ActivitiesTab(store: coordinator.externalActivities)
        case .notes: NotesTab(notes: coordinator.notes, model: model)
        case .timer: TimerTab(coordinator: coordinator)
        case .system: SystemTab(stats: coordinator.systemStats)
        case .mirror: MirrorTab(mirror: coordinator.mirror)
        case .claude: ClaudeTab(usage: coordinator.claudeUsage)
        }
    }
}

extension NotchTab {
    /// İçerik alanının istediği boyut (bant ve şerit hariç). Ayna kare, takvim geniş, not yüksek,
    /// zamanlayıcı dar.
    var bodySize: CGSize {
        switch self {
        case .media: CGSize(width: 560, height: 132)
        case .calendar: CGSize(width: 640, height: 124)
        case .shelf: CGSize(width: 560, height: 104)
        case .activities: CGSize(width: 560, height: 120)
        case .notes: CGSize(width: 560, height: 196)
        case .timer: CGSize(width: 480, height: 84)
        case .system: CGSize(width: 560, height: 88)
        case .mirror: CGSize(width: 400, height: 300)
        case .claude: CGSize(width: 560, height: 150)
        }
    }
}

/// Bantta, çentiğin solunda: bulunulan sekme. Sığmazsa yalnız simge.
private struct SectionTitle: View {
    let tab: NotchTab

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Label(tab.title, systemImage: tab.symbol).labelStyle(.titleAndIcon)
            Image(systemName: tab.symbol)
        }
        .font(NotchDesign.title)
        .lineLimit(1)
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

/// Sekme şeridi: seçili sekme simge ve adıyla, diğerleri yalnız simgeyle; seçim kayan bir zeminle
/// geçer. Ad sığmıyorsa hepsi simge.
private struct TabStrip: View {
    let tabs: [NotchTab]
    let selected: NotchTab
    let availableWidth: CGFloat
    let select: (NotchTab) -> Void
    @Namespace private var selection

    var body: some View {
        let showsLabel = estimatedWidth(withLabel: true) <= availableWidth
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
                TabButton(tab: tab, isSelected: tab == selected, showsLabel: showsLabel && tab == selected,
                          namespace: selection) { select(tab) }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func estimatedWidth(withLabel: Bool) -> CGFloat {
        let icons = CGFloat(tabs.count) * 32 + CGFloat(max(0, tabs.count - 1)) * 2
        return icons + (withLabel ? CGFloat(selected.title.count) * 7 + 8 : 0)
    }
}

private struct TabButton: View {
    let tab: NotchTab
    let isSelected: Bool
    let showsLabel: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: tab.symbol).font(.system(size: 12, weight: .semibold))
                if showsLabel {
                    Text(tab.title).font(NotchDesign.captionEmphasized).lineLimit(1).fixedSize()
                }
            }
            .padding(.horizontal, 10)
            .frame(minWidth: 32, minHeight: NotchDesign.stripHeight)
            .foregroundStyle(isSelected ? Color.white : Color.white.opacity(isHovering ? 0.85 : 0.5))
            .background {
                if isSelected {
                    Capsule().fill(NotchDesign.selectionFill).matchedGeometryEffect(id: "selection", in: namespace)
                } else if isHovering {
                    Capsule().fill(NotchDesign.cardFill)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .notchAnimation(NotchMotion.hover, value: isHovering)
        .help(tab.title)
        .accessibilityLabel(tab.title)
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
