import Integrations
import NotchShell
import SwiftUI

struct SettingsView: View {
    let coordinator: AppCoordinator
    @Bindable var settings: AppSettings

    var body: some View {
        TabView {
            GeneralSettings(settings: settings)
                .tabItem { Label("Genel", systemImage: "gearshape") }
            ModuleSettings(coordinator: coordinator, settings: settings)
                .tabItem { Label("Modüller", systemImage: "square.grid.2x2") }
            TabSettings(coordinator: coordinator, settings: settings)
                .tabItem { Label("Sekmeler", systemImage: "rectangle.split.3x1") }
            AboutSettings()
                .tabItem { Label("Hakkında", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 480)
    }
}

private struct GeneralSettings: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            if !settings.hasCompletedOnboarding {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Hoş geldiniz").font(.headline)
                        Text("İmleci çentiğin üstüne getirince notch açılır; tıklarsanız açık kalır. İki parmakla aşağı kaydırmak da açar. Dosyaları çentiğe sürükleyerek rafa bırakabilirsiniz. Takvim ve Automation izinleri yalnız ilgili özelliği kullandığınızda istenir.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button("Anladım") { settings.hasCompletedOnboarding = true }
                            .padding(.top, 4)
                    }
                }
            }
            Section("Ekranlar") {
                let displays = PanelManager.displaySummaries(for: settings.panelOptions)
                ForEach(displays) { display in
                    Picker(display.name, selection: Binding(
                        get: { display.mode },
                        set: { settings.displayModes[display.persistentID] = $0 })) {
                        ForEach(PanelManager.DisplayMode.allCases, id: \.self) {
                            Text($0.title(hasNotch: display.hasNotch)).tag($0)
                        }
                    }
                }
                Picker("Ayar verilmemiş ekranlar", selection: $settings.screenPolicy) {
                    ForEach(PanelManager.ScreenPolicy.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if displays.contains(where: { $0.mode == .automatic && !$0.hasNotch }) {
                    Picker("Çentiksiz ekranlarda hap", selection: $settings.notchlessVisibility) {
                        ForEach(PanelManager.NotchlessVisibility.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
                Text("Ekran seçimi ekranın kendisine bağlı saklanır; çıkarıp takınca korunur. Yüzen kart menü çubuğunun altında durur ve yalnız gösterecek bir şey olduğunda belirir.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Görünüm") {
                Picker("Üzerine gelince açılma gecikmesi", selection: $settings.openDelayMilliseconds) {
                    ForEach(AppSettings.openDelayChoices, id: \.self) { Text("\($0) ms").tag($0) }
                }
                Toggle("Dokunsal geri bildirim (Force Touch trackpad)", isOn: $settings.hapticsEnabled)
            }
            Section("Gizleme") {
                Toggle("Tam ekran uygulamalarda gizle", isOn: $settings.hideInFullScreen)
                Toggle("Ekran kaydı ve ekran paylaşımında gizle", isOn: $settings.hideFromScreenCapture)
                Toggle("Mission Control'de gizle", isOn: $settings.hideInMissionControl)
                Toggle("Oyunlarda gizle", isOn: $settings.hideInGames)
            }
            Section("Sistem") {
                Toggle("Girişte başlat", isOn: Binding(get: { settings.launchAtLogin },
                                                       set: { settings.launchAtLogin = $0 }))
                if settings.launchAtLoginStatus == .requiresApproval {
                    Text("Sistem Ayarları › Genel › Giriş Öğeleri'nden onay gerekiyor.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        // Açılan/kapanan satırlar (hoş geldin, çentiksiz hap seçimi, giriş öğesi onayı) birden değil geçişle.
        .notchAnimation(value: GeneralReveal(settings: settings))
    }
}

private struct ModuleSettings: View {
    let coordinator: AppCoordinator
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("Medya (Now Playing)", isOn: $settings.nowPlayingEnabled)
                Text(coordinator.nowPlayingSourceDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } footer: {
                Text("Sistem geneli kaynak macOS 15.4'ten beri public değil; mediaremote-adapter kullanılıyor. Çalışmazsa yalnız Music ve Spotify desteklenir.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Takvim ve toplantılar", isOn: $settings.calendarEnabled)
                HStack {
                    Text(calendarStatus).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    switch coordinator.calendar.access {
                    case .notDetermined:
                        Button("İzin ver") { Task { await coordinator.calendar.requestAccess() } }
                    case .denied:
                        Button("Gizlilik ayarlarını aç") { CalendarMonitor.openPrivacySettings() }
                    case .granted:
                        EmptyView()
                    }
                }
            }
            Section {
                Toggle("Etkinlik API'si (yerel soket ve notch komutu)", isOn: $settings.activityAPIEnabled)
                Text(coordinator.ui.activityAPIStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                HStack {
                    Text(coordinator.cliPath)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .textSelection(.enabled)
                    Spacer()
                    Button("Yolu kopyala") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(coordinator.cliPath, forType: .string)
                    }
                }
            } footer: {
                Text("Betikler, AI ajanları ve Kestirmeler (Kabuk Betiği Çalıştır) notch'a etkinlik gönderebilir: notch push --id build --title Derleme --progress 40%. Yalnız sizin kullanıcınız erişebilir.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker("Ses ve parlaklık göstergesi", selection: $settings.hudMode) {
                    ForEach(HUDController.Mode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if settings.hudMode == .replace {
                    HStack {
                        (coordinator.hud.isTapActive
                             ? Text("Medya tuşları yakalanıyor")
                             : Text("Erişilebilirlik izni bekleniyor; izin verince kendiliğinden başlar"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if !coordinator.hud.isTapActive {
                            Button("Erişilebilirlik ayarlarını aç") { HUDController.openAccessibilitySettings() }
                        }
                    }
                    (coordinator.hud.isBrightnessAvailable
                         ? Text("Parlaklık: yerleşik ekranda ayarlanıyor (private DisplayServices).")
                         : Text("Parlaklık: bu Mac'te ayarlanamıyor; parlaklık tuşları sisteme bırakılır."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Kamera ve mikrofon göstergesi", isOn: $settings.privacyIndicatorEnabled)
                Toggle("İndirmeler (İndirilenler klasörü izni ister)", isOn: $settings.downloadsEnabled)
            }
            Section {
                Toggle("Kilit ekranında göster (deneysel)", isOn: $settings.lockScreenEnabled)
                Text("Kilitliyken yalnız müzik, şarj, kamera/mikrofon ve ses göstergesi görünür; raf, takvim ve dış etkinlikler görünmez. Private SkyLight API kullanır: bir sorun WindowServer'ı yeniden başlatıp oturumu kapatabilir.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if settings.lockScreenAutoDisabled {
                    Text("Önceki kilit sırasında uygulama beklenmedik biçimde kapandı; özellik güvenlik için kapatıldı.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                switch coordinator.lockScreen.status {
                case .unavailable:
                    Text("Bu macOS sürümünde kullanılamıyor (SkyLight sembolleri yok).")
                        .font(.caption)
                        .foregroundStyle(.orange)
                case .failed:
                    Text("Kilit ekranı Space'i kurulamadı; özellik bu oturumda çalışmıyor.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                case .off, .ready:
                    EmptyView()
                }
            }
            Section {
                Toggle("Şarkı değişince kısa göster", isOn: $settings.trackPeekEnabled)
                Toggle("Ses çıkışı değişince göster (AirPods, hoparlör)", isOn: $settings.audioOutputAlertEnabled)
                Toggle("Uyanık tutma düğmesi", isOn: $settings.keepAwakeEnabled)
                Toggle("Hızlı not", isOn: $settings.notesEnabled)
                Toggle("Claude limitleri (durum satırından)", isOn: $settings.claudeUsageEnabled)
                Toggle("Zamanlayıcı", isOn: $settings.timerEnabled)
                Toggle("Anımsatıcılar (Takvim sekmesinde)", isOn: $settings.remindersEnabled)
                Toggle("Sistem durumu (işlemci, bellek, ağ)", isOn: $settings.systemStatsEnabled)
            }
            Section {
                Toggle("Hava durumu (Open-Meteo)", isOn: $settings.weatherEnabled)
                if settings.weatherEnabled {
                    WeatherPlaceField(settings: settings, weather: coordinator.weather)
                }
                Text("Yalnız seçtiğiniz şehrin koordinatları open-meteo.com'a gönderilir; konum izni istenmez. Yarım saatte bir güncellenir.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Ayna (kamera izni yalnız ilk kullanımda istenir)", isOn: $settings.mirrorEnabled)
            }
            Section {
                Toggle("Pil ve şarj", isOn: $settings.batteryEnabled)
                Toggle("Dosya rafı ve AirDrop", isOn: $settings.shelfEnabled)
                Text("Rafta \(coordinator.shelf.items.count) öğe")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        // HUD izin satırları, hava şehri alanı, kilit uyarıları birden değil geçişle.
        .notchAnimation(value: ModuleReveal(settings: settings, coordinator: coordinator))
    }

    private var calendarStatus: String {
        switch coordinator.calendar.access {
        case .notDetermined: String(localized: "İzin henüz istenmedi")
        case .denied: String(localized: "İzin verilmedi")
        case .granted: String(localized: "İzin var · \(coordinator.calendar.upcoming.count) yaklaşan etkinlik")
        }
    }
}

private struct AboutSettings: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    private var adapterLicense: String {
        Bundle.main.url(forResource: "mediaremote-adapter-LICENSE", withExtension: "txt")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? String(localized: "Lisans metni bulunamadı.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NotchMVP \(version)").font(.headline)
            Text("Çalışma adı; ürün adı henüz belirlenmedi.")
                .foregroundStyle(.secondary)
            Divider()
            Text("Üçüncü taraf yazılım").font(.subheadline.weight(.semibold))
            Text("mediaremote-adapter (ungive), BSD-3-Clause. Değiştirilmeden, ayrı süreç olarak kullanılır.")
                .font(.callout)
            ScrollView {
                Text(adapterLicense)
                    .font(.system(size: 10.5, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(20)
    }
}

/// Şehir arama: yazılan adın ilk sonucu seçilir.
private struct WeatherPlaceField: View {
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

/// Sekmelerin sırası ve görünürlüğü. Modülü kapalı sekme listede kalır ama notch'ta görünmez.
private struct TabSettings: View {
    let coordinator: AppCoordinator
    @Bindable var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            List {
                ForEach(settings.orderedTabs) { tab in
                    HStack(spacing: 10) {
                        Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                        Image(systemName: tab.symbol).frame(width: 20)
                        Text(tab.title)
                        Spacer()
                        if !coordinator.isModuleEnabled(for: tab) {
                            Text("Modül kapalı").font(.caption).foregroundStyle(.secondary)
                        }
                        Toggle(tab.title, isOn: Binding(
                            get: { !settings.hiddenTabs.contains(tab) },
                            set: { visible in
                                if visible { settings.hiddenTabs.remove(tab) } else { settings.hiddenTabs.insert(tab) }
                            }))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    .padding(.vertical, 2)
                }
                .onMove { source, destination in
                    var order = settings.orderedTabs
                    order.move(fromOffsets: source, toOffset: destination)
                    settings.tabOrder = order
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            Text("Sürükleyerek sıralayın. Kapattığınız sekme notch'ta görünmez; modülü kapalı sekme Modüller'den açılır.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Varsayılan sıraya dön") {
                settings.tabOrder = []
                settings.hiddenTabs = []
            }
        }
        .padding()
    }
}

/// Genel ayarlarda satır gösterip gizleyen durumlar.
private struct GeneralReveal: Equatable {
    let onboarding: Bool, policy: PanelManager.ScreenPolicy, modes: [String: PanelManager.DisplayMode], approval: Bool

    @MainActor
    init(settings: AppSettings) {
        onboarding = settings.hasCompletedOnboarding
        policy = settings.screenPolicy
        modes = settings.displayModes
        approval = settings.launchAtLoginStatus == .requiresApproval
    }
}

/// Modül ayarlarında satır gösterip gizleyen durumlar.
private struct ModuleReveal: Equatable {
    let hud: HUDController.Mode, tap: Bool, weather: Bool, place: String?, lockDisabled: Bool, lock: LockScreenPresenter.Status

    @MainActor
    init(settings: AppSettings, coordinator: AppCoordinator) {
        hud = settings.hudMode
        tap = coordinator.hud.isTapActive
        weather = settings.weatherEnabled
        place = settings.weatherPlace?.name
        lockDisabled = settings.lockScreenAutoDisabled
        lock = coordinator.lockScreen.status
    }
}
