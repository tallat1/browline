import Integrations
import NotchShell
import SwiftUI

/// Açık notch: çentik bandının solunda sekmeler, sağında durum; altında seçili sekme.
struct ExpandedView: View {
    let context: NotchContext
    let model: NotchSurfaceModel
    let coordinator: AppCoordinator

    private static let horizontalPadding: CGFloat = 18

    var body: some View {
        let ui = coordinator.ui
        let tabs = coordinator.availableTabs
        let sideWidth = max(0, (context.size.width - context.notchGapWidth) / 2 - Self.horizontalPadding)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                tabBar(tabs, selected: ui.selectedTab)
                    .frame(width: sideWidth, alignment: .leading)
                Spacer(minLength: context.notchGapWidth)
                statusArea
                    .frame(width: sideWidth, alignment: .trailing)
            }
            .frame(height: context.bandHeight)

            Group {
                if tabs.isEmpty {
                    Text("Tüm modüller kapalı. Menü çubuğundaki simgeden Ayarlar'ı açın.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    switch ui.selectedTab {
                    case .media: MediaTab(nowPlaying: coordinator.nowPlaying,
                                          sourceDescription: coordinator.nowPlayingSourceDescription)
                    case .calendar: CalendarTab(calendar: coordinator.calendar)
                    case .shelf: ShelfTab(shelf: coordinator.shelf)
                    case .activities: ActivitiesTab(store: coordinator.externalActivities)
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, Self.horizontalPadding)
        .foregroundStyle(.white)
        .onChange(of: model.isFileDragActive, initial: true) { _, dragging in
            if dragging, tabs.contains(.shelf) { ui.selectedTab = .shelf }
        }
    }

    private func tabBar(_ tabs: [NotchTab], selected: NotchTab) -> some View {
        HStack(spacing: 4) {
            ForEach(tabs) { tab in
                Button {
                    coordinator.ui.selectedTab = tab
                } label: {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 22)
                        .background(Capsule().fill(.white.opacity(tab == selected ? 0.18 : 0)))
                        .foregroundStyle(tab == selected ? .white : .secondary)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(tab.title)
            }
        }
    }

    @ViewBuilder
    private var statusArea: some View {
        if coordinator.settings.batteryEnabled, let state = coordinator.battery.state {
            HStack(spacing: 4) {
                Text("%\(state.percent)").monospacedDigit()
                Image(systemName: state.symbolName)
                    .foregroundStyle(state.isCharging ? .green : (state.percent <= 20 ? .red : .white))
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
        }
    }
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
