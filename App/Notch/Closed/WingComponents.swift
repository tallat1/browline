import ActivityAPI
import ActivityEngine
import Integrations
import NotchShell
import SwiftUI

/// Geniş kanatta simge + metin. Metin sığmazsa bir kez kayarak tamamı gösterilir (kesilmez);
/// kısa bildirimin süresi `AppCoordinator.readableFlashDuration` ile buna göre uzar.
struct WideWingLabel: View {
    let symbol: String
    let tint: Color
    let text: String

    /// Kanatta metne kalan genişlik: kanat − baş boşluk (12) − simge (~16) − aralık (6).
    static var textWidth: CGFloat { AppCoordinator.wideWingWidth - 34 }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(tint)
            MarqueeText(text: text, size: 13, weight: .semibold)
        }
        .padding(.leading, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Bluetooth kısa bildiriminin sağ kanadı: bağlanınca pil, azalınca kırmızı pil, ayrılınca "Ayrıldı".
struct BluetoothEventDetail: View {
    let event: BluetoothEvent

    var body: some View {
        switch event.change {
        case .disconnected:
            Text("Ayrıldı").foregroundStyle(.secondary)
        case let .lowBattery(level):
            BatteryLevelLabel(level: level, tint: .red)
        case .connected:
            if let level = event.device.lowest {
                BatteryLevelLabel(level: level, tint: level <= 20 ? .red : .secondary)
            }
        }
    }
}

/// Aygıt pili: simge ve yerel yüzde ("%80" / "80%").
struct BatteryLevelLabel: View {
    let level: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(verbatim: NowFormat.percent(Double(level))).monospacedDigit()
            Image(systemName: BluetoothMonitor.Device.batterySymbol(for: level))
        }
        .foregroundStyle(tint)
    }
}
