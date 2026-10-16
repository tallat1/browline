import Integrations
import NotchShell
import SwiftUI

// MARK: - Notch

struct NotchSettingsPage: View {
    let coordinator: AppCoordinator
    @Bindable var settings: AppSettings

    var body: some View {
        SettingsForm(page: .notch) {
            Section("Açılma") {
                Picker("Üzerine gelince açılma", selection: $settings.openDelayMilliseconds) {
                    ForEach(AppSettings.openDelayChoices, id: \.self) { Text(AppSettings.openDelayTitle($0)).tag($0) }
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
