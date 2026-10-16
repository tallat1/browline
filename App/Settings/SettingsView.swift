import Integrations
import NotchShell
import SwiftUI

/// Ayarlar: Sistem Ayarları gibi kenar çubuğu (Genel, Notch, İzinler · notch'un beş bölümü · Diğer ·
/// Hakkında) ve sayfa başına gruplu form. 2026-10-16 tasarım denetimi: dört üst sekmede 31 seçenek
/// başlıksız tek listedeydi, bir özellik iki yerde açılıp kapanıyordu. Rakip araştırması (Atoll,
/// boring.notch, DynamicNotch) kenar çubuğu, sayfa içi izin ve aramayı doğruladı.
struct SettingsView: View {
    let coordinator: AppCoordinator
    @Bindable var settings: AppSettings
    @State private var query = ""
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        let ui = coordinator.ui
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 214, max: 260)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            ScrollViewReader { proxy in
                page(ui.settingsPage)
                    .id(ui.settingsPage)
                    .environment(\.settingsHighlight, ui.settingsHighlight)
                    .onChange(of: ui.settingsHighlight, initial: true) { _, id in
                        guard let id else { return }
                        // Sayfa çizildikten sonra kaydır; vurgu kısa süre kalır.
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(120))
                            withAnimation { proxy.scrollTo(id, anchor: .center) }
                            try? await Task.sleep(for: .seconds(1.8))
                            if ui.settingsHighlight == id { ui.settingsHighlight = nil }
                        }
                    }
            }
        }
        .frame(minWidth: 760, minHeight: 540)
    }

    private var sidebar: some View {
        let ui = coordinator.ui
        return List(selection: Binding(get: { ui.settingsPage }, set: { if let page = $0 { ui.settingsPage = page } })) {
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                ForEach(SettingsPage.Group.allCases, id: \.self) { group in
                    let pages = SettingsPage.allCases.filter { $0.group == group }
                    if let title = group.title {
                        Section(title) { rows(pages) }
                    } else {
                        Section { rows(pages) }
                    }
                }
            } else {
                let results = SettingsSearch.results(for: query)
                if results.isEmpty {
                    Text("Sonuç yok").foregroundStyle(.secondary)
                } else {
                    Section("Sonuçlar") {
                        ForEach(results) { entry in
                            Button {
                                ui.settingsPage = entry.page
                                ui.settingsHighlight = entry.id
                            } label: {
                                HStack(spacing: 8) {
                                    SettingsIcon(symbol: entry.page.symbol, tint: entry.page.tint)
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(verbatim: entry.title).lineLimit(1)
                                        Text(verbatim: entry.page.title).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Ara", text: $query)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .onSubmit {
                        if let first = SettingsSearch.results(for: query).first {
                            ui.settingsPage = first.page
                            ui.settingsHighlight = first.id
                        }
                    }
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain)
                        .help("Aramayı temizle")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.07)))
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 4)
        }
    }

    private func rows(_ pages: [SettingsPage]) -> some View {
        ForEach(pages) { page in
            HStack(spacing: 8) {
                SettingsIcon(symbol: page.symbol, tint: page.tint)
                Text(verbatim: page.title)
            }
            .tag(page)
        }
    }

    @ViewBuilder
    private func page(_ page: SettingsPage) -> some View {
        switch page {
        case .general: GeneralPage(settings: settings)
        case .notch: NotchPage(coordinator: coordinator, settings: settings)
        case .permissions: PermissionsPage(center: coordinator.permissions)
        case .now: NowPage(coordinator: coordinator, settings: settings)
        case .shelf: ShelfPage(coordinator: coordinator, settings: settings)
        case .calendar: CalendarPage(coordinator: coordinator, settings: settings)
        case .tools: ToolsPage(coordinator: coordinator, settings: settings)
        case .status: StatusPage(coordinator: coordinator, settings: settings)
        case .indicators: IndicatorsPage(coordinator: coordinator, settings: settings)
        case .lockScreen: LockScreenPage(coordinator: coordinator, settings: settings)
        case .advanced: AdvancedPage(coordinator: coordinator)
        case .about: AboutPage(coordinator: coordinator)
        }
    }
}

/// Şehir arama: yazılan adın ilk sonucu seçilir.
struct WeatherPlaceField: View {
    @Bindable var settings: AppSettings
    let weather: WeatherMonitor
    @State private var query = ""
    @State private var isSearching = false
    @State private var error: String?

    var body: some View {
        HStack {
            TextField("Şehir", text: $query, prompt: Text(settings.weatherPlace?.name ?? String(localized: "Örnek: İstanbul")))
                .onSubmit(search)
            Button("Bul", action: search).disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
        }
        if let place = settings.weatherPlace {
            HStack(spacing: 6) {
                Text(verbatim: [place.name, place.country].compactMap { $0 }.joined(separator: ", "))
                if let conditions = weather.conditions {
                    Image(systemName: WeatherMonitor.symbolName(code: conditions.code, isDay: conditions.isDay))
                        .symbolRenderingMode(.multicolor)
                    Text(verbatim: "\(Int(conditions.temperature.rounded()))°")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        if let error {
            Text(error).font(.caption).foregroundStyle(.orange)
        }
    }

    private func search() {
        let name = query.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isSearching = true
        Task { @MainActor in
            defer { isSearching = false }
            do {
                settings.weatherPlace = try await WeatherMonitor.geocode(name)
                error = nil
                query = ""
            } catch {
                self.error = String(localized: "Şehir bulunamadı: \(name)")
            }
        }
    }
}

/// İzlenen depolar: ekle, kaldır, son çalışılan depoları öner; yalnız benimkiler.
struct CIRepositorySettings: View {
    @Bindable var settings: AppSettings
    let ci: CIMonitor
    @State private var draft = ""
    @State private var suggestions: [String] = []
    @State private var isSearching = false

    var body: some View {
        ForEach(settings.ciRepositories, id: \.self) { repository in
            HStack {
                Image(systemName: "hammer").foregroundStyle(.secondary)
                Text(verbatim: repository)
                Spacer()
                Button {
                    settings.ciRepositories.removeAll { $0 == repository }
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("İzlemeyi bırak")
            }
        }
        HStack {
            TextField("sahip/depo ya da GitHub adresi", text: $draft)
                .onSubmit(add)
            Button("Ekle", action: add)
                .disabled(CIMonitor.normalize(draft) == nil)
        }
        HStack {
            Button(isSearching ? "Aranıyor…" : "Son çalıştığım depoları öner") { suggest() }
                .disabled(isSearching)
            ForEach(suggestions.filter { !settings.ciRepositories.contains($0) }, id: \.self) { repository in
                Button(repository) { settings.ciRepositories.append(repository) }
                    .buttonStyle(.link)
            }
        }
        Toggle("Yalnız benim başlattığım çalışmalar", isOn: $settings.ciOnlyMine)
        Text(statusText)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var statusText: String {
        switch ci.status {
        case .missingTool: String(localized: "gh bulunamadı: Terminal'de brew install gh, sonra gh auth login.")
        case let .failed(repository): String(localized: "\(repository) okunamadı; gh auth status ile kontrol edin.")
        case .idle, .running:
            String(localized: "Süren çalışma varken 30 sn'de bir, yoksa 3 dk'da bir sorulur. Anahtar uygulamaya gelmez; gh kendi oturumunu kullanır.")
        }
    }

    private func add() {
        guard let repository = CIMonitor.normalize(draft) else { return }
        if !settings.ciRepositories.contains(repository) { settings.ciRepositories.append(repository) }
        draft = ""
    }

    /// ~/GitHub (yoksa ev klasörü) altındaki git depoları; son 14 günde commit alan GitHub depoları.
    private func suggest() {
        isSearching = true
        let home = FileManager.default.homeDirectoryForCurrentUser
        let github = home.appendingPathComponent("GitHub")
        let root = FileManager.default.fileExists(atPath: github.path) ? github : home
        Task {
            let found = await Task.detached(priority: .utility) { CIMonitor.suggestedRepositories(in: root) }.value
            suggestions = found
            isSearching = false
        }
    }
}
