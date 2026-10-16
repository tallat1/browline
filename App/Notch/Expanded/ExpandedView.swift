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
        case .shelf: ShelfTab(shelf: coordinator.shelf, isTargeted: model.isDropTargeted)
        case .activities: ActivitiesTab(store: coordinator.externalActivities)
        case .notes: NotesTab(notes: coordinator.notes, model: model)
        case .timer: TimerTab(coordinator: coordinator)
        case .system: SystemTab(stats: coordinator.systemStats,
                                bluetooth: coordinator.settings.bluetoothEnabled ? coordinator.bluetooth : nil)
        case .mirror: MirrorTab(mirror: coordinator.mirror)
        case .claude: ClaudeTab(usage: coordinator.claudeUsage)
        case .terminal: TerminalTab(session: coordinator.terminal, model: model)
        case .clipboard: ClipboardTab(history: coordinator.clipboard)
        case .ci: CITab(ci: coordinator.ci, hasRepositories: !coordinator.settings.ciRepositories.isEmpty,
                        openSettings: { coordinator.showSettings(.status, highlight: "ci") })
        }
    }
}
