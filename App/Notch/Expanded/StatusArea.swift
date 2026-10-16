import ActivityAPI
import AppKit
import Integrations
import NotchShell
import SwiftUI

/// Bantta, çentiğin sağında: hava, uyanık tutma, gizlilik, pil. Sığmadıkça azalır; pil en son gider.
struct StatusArea: View {
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
            // Fincan yalnız uyanık tutma açıkken (kapatmak için); açmak Araçlar › Zamanlayıcı'da ve menü
            // çubuğunda. Hep görünen fincan durum alanını kalabalıklaştırıyordu (2026-10-16 denetimi).
            if full, coordinator.settings.keepAwakeEnabled, coordinator.keepAwake.isActive {
                KeepAwakeButton(keepAwake: coordinator.keepAwake).notchTransition(.fade)
            }
            // Kamera yeşil, mikrofon turuncu: macOS menü çubuğu göstergeleriyle aynı renkler.
            if coordinator.privacy.isCameraActive {
                Circle().fill(.green).frame(width: 6, height: 6).help("Kamera kullanımda").notchTransition(.fade)
            }
            if coordinator.screenRecording.isRecording {
                Circle().fill(.purple).frame(width: 6, height: 6).help("Ekran kaydediliyor ya da paylaşılıyor")
                    .notchTransition(.fade)
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
    let weather: Bool, keepAwake: Bool, camera: Bool, microphone: Bool, screen: Bool, battery: Int?

    @MainActor
    init(coordinator: AppCoordinator) {
        weather = coordinator.weather.conditions != nil
        keepAwake = coordinator.keepAwake.isActive
        camera = coordinator.privacy.isCameraActive
        microphone = coordinator.privacy.isMicrophoneActive
        screen = coordinator.screenRecording.isRecording
        battery = coordinator.battery.state?.percent
    }
}

private struct KeepAwakeButton: View {
    let keepAwake: KeepAwake

    var body: some View {
        Button {
            if keepAwake.isActive { keepAwake.stop() } else { keepAwake.start(reason: String(localized: "Browline: uyanık tut")) }
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
