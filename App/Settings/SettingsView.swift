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
                        Text("İmleci çentiğin üstüne getirince notch açılır; tıklarsanız açık kalır. "
                             + "İki parmakla aşağı kaydırmak da açar. Dosyaları çentiğe sürükleyerek rafa bırakabilirsiniz. "
                             + "Takvim ve Automation izinleri yalnız ilgili özelliği kullandığınızda istenir.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button("Anladım") { settings.hasCompletedOnboarding = true }
                            .padding(.top, 4)
                    }
                }
            }
            Section("Görünüm") {
                Picker("Ekranlar", selection: $settings.screenPolicy) {
                    ForEach(PanelManager.ScreenPolicy.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Üzerine gelince açılma gecikmesi", selection: $settings.openDelayMilliseconds) {
                    ForEach(AppSettings.openDelayChoices, id: \.self) { Text("\($0) ms").tag($0) }
                }
                Toggle("Dokunsal geri bildirim (Force Touch trackpad)", isOn: $settings.hapticsEnabled)
            }
            Section("Gizleme") {
                Toggle("Tam ekran uygulamalarda gizle", isOn: $settings.hideInFullScreen)
                Toggle("Ekran kaydı ve ekran paylaşımında gizle", isOn: $settings.hideFromScreenCapture)
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
                Text("Sistem geneli kaynak macOS 15.4'ten beri public değil; mediaremote-adapter kullanılıyor. "
                     + "Çalışmazsa yalnız Music ve Spotify desteklenir.")
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
                Toggle("Pil ve şarj", isOn: $settings.batteryEnabled)
                Toggle("Dosya rafı ve AirDrop", isOn: $settings.shelfEnabled)
                Text("Rafta \(coordinator.shelf.items.count) öğe")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var calendarStatus: String {
        switch coordinator.calendar.access {
        case .notDetermined: "İzin henüz istenmedi"
        case .denied: "İzin verilmedi"
        case .granted: "İzin var · \(coordinator.calendar.upcoming.count) yaklaşan etkinlik"
        }
    }
}

private struct AboutSettings: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    private var adapterLicense: String {
        Bundle.main.url(forResource: "mediaremote-adapter-LICENSE", withExtension: "txt")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "Lisans metni bulunamadı."
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
