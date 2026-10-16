import Integrations
import NotchShell
import SwiftUI

/// Bir ayar sayfasının iskeleti: başlık + gruplu form. Satırlar `settingsAnchor` ile aranabilir.
struct SettingsForm<Content: View>: View {
    let page: SettingsPage
    @ViewBuilder let content: Content

    var body: some View {
        Form {
            // Başlık bir satır olarak (zeminsiz): boş bölümün başlığı olunca ilk grup başlığı farklı çiziliyordu.
            Section {
                SettingsPageHeader(page: page)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }
            content
        }
        .formStyle(.grouped)
    }
}

// MARK: - Genel

struct GeneralPage: View {
    @Bindable var settings: AppSettings

    var body: some View {
        SettingsForm(page: .general) {
            if !settings.hasCompletedOnboarding {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Hoş geldiniz").font(.headline)
                        Text("İmleci çentiğin üstüne getirince notch açılır; tıklarsanız açık kalır. İki parmakla aşağı kaydırmak da açar. Dosyaları çentiğe sürükleyerek rafa bırakabilirsiniz. İzinler yalnız ilgili özelliği kullandığınızda istenir.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button("Anladım") { settings.hasCompletedOnboarding = true }
                            .padding(.top, 4)
                    }
                }
            }
            Section("Başlangıç") {
                Toggle("Girişte başlat", isOn: Binding(get: { settings.launchAtLogin },
                                                       set: { settings.launchAtLogin = $0 }))
                    .settingsAnchor("launchAtLogin")
                if settings.launchAtLoginStatus == .requiresApproval {
                    SettingsNote("Sistem Ayarları › Genel › Giriş Öğeleri'nden onay gerekiyor.")
                }
            }
            Section {
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
                Picker("Sonradan takılan ekranlar", selection: $settings.screenPolicy) {
                    ForEach(PanelManager.ScreenPolicy.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if displays.contains(where: { $0.mode == .automatic && !$0.hasNotch }) {
                    Picker("Çentiksiz ekranlarda hap", selection: $settings.notchlessVisibility) {
                        ForEach(PanelManager.NotchlessVisibility.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
            } header: {
                Text("Ekranlar").settingsAnchor("displays")
            } footer: {
                SettingsNote("Seçim ekrana bağlı saklanır; çıkarıp takınca korunur. Çentiksiz ekranda hap, istenirse menü çubuğunun altında yüzen kart görünür.")
            }
        }
        .animation(.default, value: settings.hasCompletedOnboarding)
    }
}

// MARK: - Notch

struct NotchPage: View {
    let coordinator: AppCoordinator
    @Bindable var settings: AppSettings

    var body: some View {
        SettingsForm(page: .notch) {
            Section("Açılma") {
                Picker("Üzerine gelince açılma", selection: $settings.openDelayMilliseconds) {
                    ForEach(AppSettings.openDelayChoices, id: \.self) { Text("\($0) ms").tag($0) }
                }
                .settingsAnchor("openDelay")
                Toggle("Dokunsal geri bildirim", isOn: $settings.hapticsEnabled)
                    .settingsAnchor("haptics")
                SettingsNote("Force Touch trackpad'de sekmeler arasında gezerken hafif tık.")
            }
            Section("Sağ üstteki durum alanı") {
                Toggle("Hava durumu", isOn: $settings.weatherEnabled)
                    .settingsAnchor("weather")
                if settings.weatherEnabled {
                    WeatherPlaceField(settings: settings, weather: coordinator.weather)
                    SettingsNote("Yalnız seçtiğiniz şehrin koordinatları Open-Meteo'ya gider; konum izni istenmez.")
                }
                Toggle("Uyanık tutma düğmesi", isOn: $settings.keepAwakeEnabled)
                    .settingsAnchor("keepAwake")
                Toggle("Pil ve şarj", isOn: $settings.batteryEnabled)
                    .settingsAnchor("battery")
                SettingsNote("Pil yüzdesi; şarj takılıp çıkarılınca ve pil azalınca kısa gösterge.")
            }
            Section("Hareket") {
                Toggle("Çalarken hareketli çubuklar", isOn: $settings.animatedEqualizer)
                    .settingsAnchor("equalizer")
                if settings.animatedEqualizer {
                    Toggle("Çubuklar müziğe tepki versin", isOn: $settings.reactiveEqualizer)
                        .padding(.leading, 16)
                        .settingsAnchor("reactive")
                    if settings.reactiveEqualizer {
                        PermissionRow(kind: .systemAudio, center: coordinator.permissions)
                    }
                }
                Toggle("Düşük Güç Modu'nda hareketi durdur", isOn: $settings.pauseMotionInLowPower)
                    .settingsAnchor("lowPower")
                SettingsNote("Çubuklar, kayan yazılar ve müzik dinleyicisi durur; kısa geçişler sürer.")
            }
            Section("Gizleme") {
                Toggle("Tam ekran uygulamalarda gizle", isOn: $settings.hideInFullScreen)
                    .settingsAnchor("hiding")
                Toggle("Ekran kaydı ve paylaşımında gizle", isOn: $settings.hideFromScreenCapture)
                Toggle("Mission Control'de gizle", isOn: $settings.hideInMissionControl)
                Toggle("Oyunlarda gizle", isOn: $settings.hideInGames)
            }
        }
        .animation(.default, value: [settings.weatherEnabled, settings.animatedEqualizer, settings.reactiveEqualizer])
    }
}

// MARK: - İzinler

struct PermissionsPage: View {
    let center: PermissionCenter

    var body: some View {
        let needed = PermissionKind.allCases.filter(center.isNeeded)
        let unused = PermissionKind.allCases.filter { !center.isNeeded($0) }
        SettingsForm(page: .permissions) {
            Section {
                if needed.isEmpty {
                    SettingsNote("Açık özelliklerin hiçbiri izin istemiyor.")
                } else {
                    ForEach(needed) { PermissionRow(kind: $0, center: center, showsIcon: true) }
                }
            } header: {
                Text("Açık özellikler için")
            } footer: {
                SettingsNote("İzin her özelliğin kendi sayfasında da görünür. Sistem Ayarları'ndan dönünce durum kendiliğinden yenilenir.")
            }
            if !unused.isEmpty {
                Section("Kullanılmayan") {
                    ForEach(unused) { kind in
                        HStack(spacing: 10) {
                            SettingsIcon(symbol: kind.symbol, tint: .gray, size: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: kind.systemName)
                                Text(verbatim: kind.purpose).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("Özellik kapalı").font(.caption).foregroundStyle(.secondary)
                        }
                        .settingsAnchor("permission.\(kind.rawValue)")
                    }
                }
            }
        }
        .onAppear { center.refresh() }
    }
}

// MARK: - Şimdi

struct NowPage: View {
    let coordinator: AppCoordinator
    @Bindable var settings: AppSettings

    var body: some View {
        SettingsForm(page: .now) {
            Section("Medya") {
                Toggle("Çalan müzik ve video", isOn: $settings.nowPlayingEnabled)
                    .settingsAnchor("media")
                SettingsNote("Spotify, Music, tarayıcı ve diğer oynatıcılar; birden çok oynatıcı varsa seçilebilir.")
                if settings.nowPlayingEnabled, coordinator.permissions.status(.automation) != .granted {
                    PermissionRow(kind: .automation, center: coordinator.permissions)
                }
            }
            Section("Toplantı") {
                Toggle("Mikrofonu sistem genelinde sessize alma", isOn: $settings.meetingControlsEnabled)
                    .settingsAnchor("meeting")
                if settings.meetingControlsEnabled {
                    Picker("Kısayol", selection: $settings.micShortcut) {
                        ForEach(GlobalShortcut.Preset.allCases) { Text(verbatim: $0.title).tag($0) }
                    }
                    .padding(.leading, 16)
                    .settingsAnchor("micShortcut")
                    if coordinator.ui.micShortcutUnavailable {
                        SettingsNote("Bu kısayol başka bir uygulamada kayıtlı; başka birini seçin.", tint: .red)
                    } else {
                        SettingsNote("Mikrofon kullanımdayken Şimdi'de kart; hangi uygulama öndeyse olsun kısayolla da.")
                    }
                }
            }
            Section("Dış etkinlikler") {
                Toggle("Betik ve AI ajanı etkinlikleri", isOn: $settings.activityAPIEnabled)
                    .settingsAnchor("activities")
                Toggle("Claude Code izin istemlerini notch'ta yanıtla", isOn: $settings.questionsEnabled)
                    .disabled(!settings.activityAPIEnabled)
                    .padding(.leading, 16)
                    .settingsAnchor("questions")
                SettingsNote("Derleme ilerlemesi, Claude oturumları ve Kestirmeler Şimdi'de kart olarak görünür. Komut satırı ayrıntıları Gelişmiş'te.")
            }
        }
        .onAppear { coordinator.permissions.refresh() }
        .animation(.default, value: settings.meetingControlsEnabled)
    }
}

// MARK: - Raf

struct ShelfPage: View {
    let coordinator: AppCoordinator
    @Bindable var settings: AppSettings

    var body: some View {
        SettingsForm(page: .shelf) {
            Section("Dosyalar") {
                Toggle("Dosya rafı", isOn: $settings.shelfEnabled)
                    .settingsAnchor("shelf")
                ShowInNotchToggle(settings: settings, tab: .shelf, isFeatureEnabled: settings.shelfEnabled)
                SettingsNote("Ekran görüntüsü küçük resimleri \(ShelfStore.promiseDestination().lastPathComponent) klasörüne kaydedilir. Rafta \(coordinator.shelf.items.count) öğe.")
            }
            Section("Pano geçmişi") {
                Toggle("Pano geçmişi", isOn: $settings.clipboardEnabled)
                    .settingsAnchor("clipboard")
                ShowInNotchToggle(settings: settings, tab: .clipboard, isFeatureEnabled: settings.clipboardEnabled)
                SettingsNote("Son 50 kopya, yalnız bellekte. Parola yöneticilerinin gizli kopyaları alınmaz.")
            }
        }
    }
}

// MARK: - Takvim

struct CalendarPage: View {
    let coordinator: AppCoordinator
    @Bindable var settings: AppSettings

    var body: some View {
        SettingsForm(page: .calendar) {
            Section("Takvim") {
                Toggle("Takvim ve toplantılar", isOn: $settings.calendarEnabled)
                    .settingsAnchor("calendar")
                ShowInNotchToggle(settings: settings, tab: .calendar, isFeatureEnabled: settings.calendarEnabled)
                if settings.calendarEnabled {
                    PermissionRow(kind: .calendar, center: coordinator.permissions)
                }
            }
            Section("Anımsatıcılar") {
                Toggle("Bugünün anımsatıcıları", isOn: $settings.remindersEnabled)
                    .disabled(!settings.calendarEnabled)
                    .settingsAnchor("reminders")
                if settings.calendarEnabled, settings.remindersEnabled {
                    PermissionRow(kind: .reminders, center: coordinator.permissions)
                }
                SettingsNote("Takvim sayfasının sağ sütununda; daireye basınca tamamlanır.")
            }
        }
        .onAppear { coordinator.permissions.refresh() }
        .animation(.default, value: [settings.calendarEnabled, settings.remindersEnabled])
    }
}

// MARK: - Araçlar

struct ToolsPage: View {
    let coordinator: AppCoordinator
    @Bindable var settings: AppSettings

    var body: some View {
        SettingsForm(page: .tools) {
            Section("Not") {
                Toggle("Hızlı not", isOn: $settings.notesEnabled).settingsAnchor("notes")
                ShowInNotchToggle(settings: settings, tab: .notes, isFeatureEnabled: settings.notesEnabled)
            }
            Section("Zamanlayıcı") {
                Toggle("Zamanlayıcı ve Pomodoro", isOn: $settings.timerEnabled).settingsAnchor("timer")
                ShowInNotchToggle(settings: settings, tab: .timer, isFeatureEnabled: settings.timerEnabled)
            }
            Section("Terminal") {
                Toggle("Terminal", isOn: $settings.terminalEnabled).settingsAnchor("terminal")
                ShowInNotchToggle(settings: settings, tab: .terminal, isFeatureEnabled: settings.terminalEnabled)
                SettingsNote("Kapatınca açık kabuk sonlanır.")
            }
            Section("Ayna") {
                Toggle("Ayna", isOn: $settings.mirrorEnabled).settingsAnchor("mirror")
                ShowInNotchToggle(settings: settings, tab: .mirror, isFeatureEnabled: settings.mirrorEnabled)
                if settings.mirrorEnabled {
                    PermissionRow(kind: .camera, center: coordinator.permissions)
                }
            }
        }
        .onAppear { coordinator.permissions.refresh() }
        .animation(.default, value: settings.mirrorEnabled)
    }
}

// MARK: - Durum

struct StatusPage: View {
    let coordinator: AppCoordinator
    @Bindable var settings: AppSettings

    var body: some View {
        SettingsForm(page: .status) {
            Section("Sistem") {
                Toggle("İşlemci, bellek ve ağ", isOn: $settings.systemStatsEnabled).settingsAnchor("system")
                ShowInNotchToggle(settings: settings, tab: .system, isFeatureEnabled: settings.systemStatsEnabled)
            }
            Section("Bluetooth") {
                Toggle("Bluetooth aygıtları", isOn: $settings.bluetoothEnabled).settingsAnchor("bluetooth")
                SettingsNote("Bağlanınca, ayrılınca ve pil %20 ile %10'un altına inince kısa gösterge; Sistem sayfasında pil kartı.")
            }
            Section("Claude") {
                Toggle("Claude limitleri", isOn: $settings.claudeUsageEnabled).settingsAnchor("claude")
                ShowInNotchToggle(settings: settings, tab: .claude, isFeatureEnabled: settings.claudeUsageEnabled)
                if settings.claudeUsageEnabled {
                    Toggle("Oturum ve hafta yüzdeleri", isOn: $settings.claudeUsageAPIEnabled)
                        .padding(.leading, 16)
                        .settingsAnchor("claudeAPI")
                    SettingsNote("Claude Code'un oturumuyla 5 dakikada bir sorulur; belgelenmemiş bir uç nokta, haber vermeden değişebilir.")
                }
            }
            Section("CI") {
                Toggle("GitHub Actions durumu", isOn: $settings.ciEnabled).settingsAnchor("ci")
                ShowInNotchToggle(settings: settings, tab: .ci, isFeatureEnabled: settings.ciEnabled)
                if settings.ciEnabled {
                    CIRepositorySettings(settings: settings, ci: coordinator.ci)
                }
            }
        }
        .animation(.default, value: [settings.claudeUsageEnabled, settings.ciEnabled])
    }
}

// MARK: - Göstergeler

struct IndicatorsPage: View {
    let coordinator: AppCoordinator
    @Bindable var settings: AppSettings

    var body: some View {
        SettingsForm(page: .indicators) {
            Section("Kısa bildirimler") {
                Toggle("Şarkı değişince", isOn: $settings.trackPeekEnabled).settingsAnchor("trackPeek")
                Toggle("Ses çıkışı değişince", isOn: $settings.audioOutputAlertEnabled).settingsAnchor("audioOutput")
                Toggle("İndirme bitince", isOn: $settings.downloadsEnabled).settingsAnchor("downloads")
                if settings.downloadsEnabled {
                    PermissionRow(kind: .downloads, center: coordinator.permissions)
                }
            }
            Section("Gizlilik göstergeleri") {
                Toggle("Kamera ve mikrofon kullanımda", isOn: $settings.privacyIndicatorEnabled).settingsAnchor("privacy")
                Toggle("Ekran kaydediliyor ya da paylaşılıyor", isOn: $settings.screenRecordingIndicatorEnabled)
                    .settingsAnchor("screenRecording")
            }
            Section("Ses ve parlaklık") {
                Picker("Gösterge", selection: $settings.hudMode) {
                    ForEach(HUDController.Mode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .settingsAnchor("hud")
                if settings.hudMode == .replace {
                    PermissionRow(kind: .accessibility, center: coordinator.permissions)
                    if !coordinator.hud.isBrightnessAvailable {
                        SettingsNote("Parlaklık bu Mac'te ayarlanamıyor; parlaklık tuşları sisteme bırakılır.")
                    }
                }
            }
        }
        .onAppear { coordinator.permissions.refresh() }
        .animation(.default, value: [settings.downloadsEnabled, settings.hudMode == .replace])
    }
}

// MARK: - Kilit ekranı

struct LockScreenPage: View {
    let coordinator: AppCoordinator
    @Bindable var settings: AppSettings

    var body: some View {
        SettingsForm(page: .lockScreen) {
            Section {
                Toggle("Müzik ve pil şeridi", isOn: $settings.lockScreenWidgetsEnabled).settingsAnchor("lockWidgets")
                SettingsNote("Kilitliyken notch genişler: solda çalan şarkı, sağda pil. Tıklanamaz; macOS'un saatini örtmez.")
            }
            Section {
                Toggle("Kilit ekranında ayrı panel (deneysel)", isOn: $settings.lockScreenEnabled).settingsAnchor("lockScreen")
                SettingsNote("Yalnız müzik, şarj, kamera/mikrofon ve ses göstergesi görünür; raf, takvim ve dış etkinlikler görünmez. Bir sorun oturumu kapatabilir.")
                if settings.lockScreenAutoDisabled {
                    SettingsNote("Önceki kilit sırasında uygulama beklenmedik biçimde kapandı; özellik güvenlik için kapatıldı.", tint: .orange)
                }
                switch coordinator.lockScreen.status {
                case .unavailable:
                    SettingsNote("Bu macOS sürümünde kullanılamıyor.", tint: .orange)
                case .failed:
                    SettingsNote("Kilit ekranı alanı kurulamadı; özellik bu oturumda çalışmıyor.", tint: .orange)
                case .off, .ready:
                    EmptyView()
                }
            }
        }
    }
}

// MARK: - Gelişmiş

struct AdvancedPage: View {
    let coordinator: AppCoordinator

    var body: some View {
        SettingsForm(page: .advanced) {
            Section {
                LabeledContent("Durum") {
                    Text(coordinator.ui.activityAPIStatus).textSelection(.enabled)
                }
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
            } header: {
                Text("Etkinlik API'si ve notch komutu").settingsAnchor("api")
            } footer: {
                SettingsNote("Betikler, AI ajanları ve Kestirmeler (Kabuk Betiği Çalıştır) yerel soketle etkinlik gönderir: notch push --id build --title Derleme --progress 40%. Yalnız sizin kullanıcınız bağlanabilir.")
            }
            Section {
                LabeledContent("Kaynak") { Text(verbatim: coordinator.nowPlayingSourceDescription).textSelection(.enabled) }
            } header: {
                Text("Medya kaynağı").settingsAnchor("source")
            } footer: {
                SettingsNote("Sistem geneli Now Playing macOS 15.4'ten beri public değil; mediaremote-adapter kullanılıyor. Çalışmazsa yalnız Music ve Spotify, AppleScript ile.")
            }
            Section {
                LabeledContent("Kilit ekranı paneli", value: "SkyLight")
                LabeledContent("Parlaklık", value: "DisplayServices")
                LabeledContent("Ekran kaydı göstergesi", value: "CGSIsScreenWatcherPresent")
                LabeledContent("Claude yüzdeleri", value: "api.anthropic.com/api/oauth/usage")
            } header: {
                Text("Belgelenmemiş macOS işlevleri").settingsAnchor("private")
            } footer: {
                SettingsNote("Bunlar çalışma anında aranır; bulunamazsa ilgili özellik kapanır, uygulama çökmez.")
            }
        }
    }
}

// MARK: - Hakkında

struct AboutPage: View {
    let coordinator: AppCoordinator

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    private static func license(_ name: String) -> String {
        Bundle.main.url(forResource: name, withExtension: "txt")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? String(localized: "Lisans metni bulunamadı.")
    }

    var body: some View {
        SettingsForm(page: .about) {
            Section {
                LabeledContent("Sürüm", value: "NotchMVP \(version)")
                    .settingsAnchor("about")
                SettingsNote("Çalışma adı; ürün adı henüz belirlenmedi.")
            }
            Section("Üçüncü taraf yazılım") {
                DisclosureGroup("mediaremote-adapter (ungive), BSD-3-Clause") {
                    licenseText(Self.license("mediaremote-adapter-LICENSE"))
                }
                DisclosureGroup("SwiftTerm (Miguel de Icaza), MIT") {
                    licenseText(Self.license("SwiftTerm-LICENSE"))
                }
            }
        }
    }

    private func licenseText(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
