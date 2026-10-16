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
                .tabItem { Label("Bölümler", systemImage: "rectangle.split.3x1") }
            AboutSettings(coordinator: coordinator)
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
                Text("Ekran seçimi ekranın kendisine bağlı saklanır; çıkarıp takınca korunur. Kapak kapalıyken yerleşik ekran yerine ana ekran kullanılır, çentiksiz ekranlarda hap görünür. Yüzen kart menü çubuğunun altında durur ve yalnız gösterecek bir şey olduğunda belirir.")
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
                Toggle("Onay sorularını notch'ta yanıtla (ör. Claude Code izin istemleri)", isOn: $settings.questionsEnabled)
                    .disabled(!settings.activityAPIEnabled)
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
                Toggle("Çalarken hareketli çubuklar (az miktarda enerji harcar)", isOn: $settings.animatedEqualizer)
                if settings.animatedEqualizer {
                    Toggle("Çubuklar müziğe tepki versin", isOn: $settings.reactiveEqualizer)
                    Text("Sistem sesinin anlık frekans dağılımı okunur; ilk açılışta macOS sistem sesi kaydı izni ister. Ses kaydedilmez, hiçbir yere gönderilmez. İzin verilmezse çubuklar eski hareketine döner.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Ses çıkışı değişince göster (AirPods, hoparlör)", isOn: $settings.audioOutputAlertEnabled)
                Toggle("Bluetooth aygıtları (bağlanınca, ayrılınca ve pili azalınca göster)",
                       isOn: $settings.bluetoothEnabled)
                Toggle("Toplantı denetimi (mikrofonu sistem genelinde sessize al)",
                       isOn: $settings.meetingControlsEnabled)
                Toggle("Uyanık tutma düğmesi", isOn: $settings.keepAwakeEnabled)
                Toggle("Hızlı not", isOn: $settings.notesEnabled)
                Toggle("Terminal (kapatınca açık kabuk sonlanır)", isOn: $settings.terminalEnabled)
                Toggle("Pano geçmişi (yalnız bellekte; parola yöneticilerinin gizli kopyaları alınmaz)",
                       isOn: $settings.clipboardEnabled)
                Toggle("Claude limitleri", isOn: $settings.claudeUsageEnabled)
                if settings.claudeUsageEnabled {
                    Toggle("Yüzdeleri kullanım uç noktasından al (belgelenmemiş)", isOn: $settings.claudeUsageAPIEnabled)
                    Text("Claude Code'un Anahtar Zinciri'ndeki oturum anahtarıyla 5 dakikada bir sorulur; anahtar yalnız bu istekte kullanılır, saklanmaz. Uç nokta haber vermeden değişebilir. Önce terminalde claude auth login gerekir.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
    let coordinator: AppCoordinator

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    private var adapterLicense: String { Self.license("mediaremote-adapter-LICENSE") }
    private var swiftTermLicense: String { Self.license("SwiftTerm-LICENSE") }

    private static func license(_ name: String) -> String {
        Bundle.main.url(forResource: name, withExtension: "txt")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? String(localized: "Lisans metni bulunamadı.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NotchMVP \(version)").font(.headline)
            Text("Çalışma adı; ürün adı henüz belirlenmedi.")
                .foregroundStyle(.secondary)
            // Tanılama: menü çubuğundan kaldırıldı (Option ile açılan menüde de var).
            Text(verbatim: coordinator.nowPlayingSourceDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Divider()
            Text("Üçüncü taraf yazılım").font(.subheadline.weight(.semibold))
            Text("mediaremote-adapter (ungive), BSD-3-Clause. Değiştirilmeden, ayrı süreç olarak kullanılır.")
                .font(.callout)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(adapterLicense)
                    Text("SwiftTerm (Miguel de Icaza), MIT. Terminal sekmesi.")
                        .font(.callout)
                    Text(swiftTermLicense)
                }
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

/// Beş bölüm ve sayfaları. Bölümler sabit; bir sayfa gizlenirse bölüm seçicisinde görünmez, bölümün
/// tüm sayfaları kapalıysa bölüm bantta da görünmez. Modülü kapalı sayfa Modüller'den açılır.
private struct TabSettings: View {
    let coordinator: AppCoordinator
    @Bindable var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            List {
                ForEach(NotchSection.allCases) { section in
                    Section {
                        ForEach(section.pages.filter { $0 != .now }) { tab in
                            row(tab)
                        }
                        if section == .now {
                            Text("Medya ve o an önemli olanlar; etkinlik kartından tüm etkinlikler açılır.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Label(section.title, systemImage: section.symbol)
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            Text("Bantta beş bölüm durur: Şimdi, Raf, Takvim, Araçlar, Durum. Birden çok sayfası olan bölümde içeriğin üstünde küçük bir seçici çıkar; her bölüm son açtığınız sayfayı hatırlar.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Hepsini göster") { settings.hiddenTabs = [] }
                .disabled(settings.hiddenTabs.isEmpty)
        }
        .padding()
    }

    private func row(_ tab: NotchTab) -> some View {
        HStack(spacing: 10) {
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
                .help("Bölüm seçicisinde göster")
        }
        .padding(.vertical, 2)
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
