import ActivityAPI
import AppKit
import Integrations
import NotchShell
import SwiftUI

/// Açık notch: tek satır başlık (bantta, çentiğin solunda beş bölüm, sağında durum), gerekirse bölümün
/// sayfa seçicisi ve altında sayfanın içeriği. Genişlik tüm sayfalarda aynı (geçişte yana zıplama
/// yok), yalnız boy içeriğe göre değişir.
struct ExpandedView: View {
    let context: NotchContext
    let model: NotchSurfaceModel
    let coordinator: AppCoordinator

    var body: some View {
        let ui = coordinator.ui
        let tabs = coordinator.availableTabs
        let page = ui.selectedTab
        let sectionPages = coordinator.pages(in: page.section)
        let sideWidth = max(0, (context.size.width - context.notchGapWidth) / 2 - context.horizontalInset)
        let question = coordinator.questions.current
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                SectionBar(sections: coordinator.availableSections, selected: page.section,
                           onHoverIcon: { model.haptic(.detent) }) { coordinator.select($0) }
                    .frame(width: sideWidth, alignment: .leading)
                Spacer(minLength: context.notchGapWidth)
                StatusArea(coordinator: coordinator).frame(width: sideWidth, alignment: .trailing)
            }
            .frame(height: context.bandHeight)

            // Bölüm seçicisi içerikle birlikte kaymaz: sayfa değişince yalnız seçim zemini kayar.
            if question == nil {
                if page.isDetailPage {
                    DetailHeader(title: page.title, back: page.section.title) { coordinator.select(page.section) }
                        .padding(.top, NotchDesign.headerSpacing)
                        .notchTransition(.fade)
                } else if sectionPages.count > 1 {
                    PagePicker(pages: sectionPages, selected: page, onHoverSegment: { model.haptic(.detent) }) {
                        ui.selectedTab = $0
                    }
                    .padding(.top, NotchDesign.headerSpacing)
                    // Bölüm değişince seçici bütün olarak anında değişir: soluklaşırken eski ve yeni
                    // bölütlerin yazıları üst üste biniyordu. Bölüm içinde yalnız zemin kayar.
                    .id(page.section)
                    .transition(.identity)
                }
            }

            // Bekleyen onay sorusu sayfanın önüne geçer; yanıtlanınca sayfa geri gelir.
            Group {
                if let question {
                    QuestionView(question: question, waitingCount: coordinator.questions.questions.count) { decision in
                        AppLog.coordinator.notice("onay sorusu yanıtlandı: \(decision?.rawValue ?? "uygulamaya bırakıldı", privacy: .public)")
                        coordinator.questions.answer(question.id, with: decision)
                    }
                } else {
                    content(page)
                }
            }
            .padding(.top, NotchDesign.headerSpacing)
            .padding(.bottom, context.bottomInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .id(question?.id ?? page.rawValue)
            .notchTransition(.swap)
        }
        // Sayfa hangi yoldan değişirse değişsin (bant, seçici, kart, dosya sürükleme, debug) içerik ve
        // seçim zemini aynı yayla geçer; şekil boyu kabukta aynı yayla akar.
        .notchAnimation(NotchMotion.resize, value: page)
        .notchAnimation(value: tabs)
        .padding(.horizontal, context.horizontalInset)
        .foregroundStyle(.white)
        .font(NotchDesign.body)
        .onChange(of: model.isFileDragActive, initial: true) { _, dragging in
            if dragging, tabs.contains(.shelf) { ui.selectedTab = .shelf }
        }
        .onChange(of: page, initial: true) { _, tab in
            model.preferredOpenSize = openSize(for: tab)
        }
        // Sayfa hangi yoldan değişirse değişsin belirgin tık.
        .onChange(of: page) { _, _ in model.haptic(.selection) }
        .onChange(of: question?.id) { _, _ in
            model.preferredOpenSize = openSize(for: page)
        }
        // Seçicinin görünüp kaybolması (bir modül açılıp kapanınca) boyu da değiştirir.
        .onChange(of: sectionPages) { _, _ in
            model.preferredOpenSize = openSize(for: page)
        }
        .notchAnimation(NotchMotion.resize, value: question?.id)
    }

    /// İstenen tüm açık boyut: bant + (seçici) + boşluk + içerik (soru varsa soru) + alt boşluk.
    private func openSize(for tab: NotchTab) -> CGSize {
        let hasQuestion = coordinator.questions.current != nil
        let body = hasQuestion ? QuestionView.height : tab.bodyHeight
        let hasHeader = !hasQuestion && (tab.isDetailPage || coordinator.pages(in: tab.section).count > 1)
        let header = hasHeader ? NotchDesign.headerSpacing + NotchDesign.Control.small : 0
        return CGSize(width: NotchDesign.openWidth,
                      height: context.bandHeight + header + NotchDesign.headerSpacing + body + context.bottomInset)
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
        // Karolar (tek satır ad) + eylem çubuğu; 104'te kesikli çerçeve gövdeden taşıyordu.
        case .shelf: 124
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

/// Bantta beş bölüm simgesi (yalnız simge; ad üzerine gelince). Seçili olan tam beyaz ve zeminli,
/// diğerleri soluk, üzerine gelince aydınlanır. Seçim kayan bir zeminle geçer.
private struct SectionBar: View {
    let sections: [NotchSection]
    let selected: NotchSection
    let onHoverIcon: () -> Void
    let select: (NotchSection) -> Void
    @Namespace private var selection

    var body: some View {
        HStack(spacing: NotchDesign.tabIconSpacing) {
            ForEach(sections) { section in
                TabIconButton(symbol: section.symbol, title: section.title, isSelected: section == selected,
                              namespace: selection, onHoverEnter: onHoverIcon) { select(section) }
                    .notchTransition(.fade)
            }
        }
        .notchAnimation(value: sections)
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

/// Bölümün sayfa seçicisi: ince bir yuva içinde simge + ad bölütleri, seçili olanın zemini kayar.
/// Yalnız birden çok sayfası olan bölümde görünür.
private struct PagePicker: View {
    let pages: [NotchTab]
    let selected: NotchTab
    let onHoverSegment: () -> Void
    let select: (NotchTab) -> Void
    @Namespace private var selection

    var body: some View {
        HStack(spacing: 2) {
            ForEach(pages) { page in
                PageSegment(page: page, isSelected: page == selected, namespace: selection,
                            onHoverEnter: onHoverSegment) { select(page) }
            }
        }
        .padding(2)
        .background(Capsule().fill(NotchDesign.cardFill))
        .overlay(Capsule().strokeBorder(NotchDesign.hairline, lineWidth: 0.5))
        .frame(height: NotchDesign.Control.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .notchAnimation(NotchMotion.resize, value: selected)
    }
}

private struct PageSegment: View {
    let page: NotchTab
    let isSelected: Bool
    let namespace: Namespace.ID
    let onHoverEnter: () -> Void
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: page.symbol)
                    .font(.system(size: 10, weight: NotchDesign.Icon.weight))
                Text(page.title).font(NotchDesign.captionEmphasized).lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(maxHeight: .infinity)
            .foregroundStyle(Color.white.opacity(isSelected ? 1 : (isHovering ? 0.9 : 0.6)))
            .background {
                if isSelected {
                    Capsule().fill(NotchDesign.selectionFill).matchedGeometryEffect(id: "page", in: namespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .onHover { inside in
            if inside, !isHovering { onHoverEnter() }
            isHovering = inside
        }
        .notchAnimation(NotchMotion.hover, value: isHovering)
        .help(page.title)
    }
}

/// Ayrıntı sayfasının başı: bölüme dönüş ve sayfa adı (ör. "‹ Şimdi · Etkinlikler").
private struct DetailHeader: View {
    let title: String
    let back: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: NotchDesign.Space.xs) {
            Button(action: action) {
                Label(back, systemImage: "chevron.left").labelStyle(.titleAndIcon)
            }
            .buttonStyle(QuietButtonStyle())
            .help("\(back)'ye dön")
            Text(verbatim: "·").foregroundStyle(.tertiary)
            Text(verbatim: title).font(NotchDesign.captionEmphasized)
            Spacer()
        }
        .frame(height: NotchDesign.Control.small)
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
