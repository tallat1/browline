import Integrations
import NotchShell
import SwiftUI

/// İşlemci, bellek, ağ. Örnekleme yalnız sekme ekrandayken (saniyede bir).
struct SystemTab: View {
    let stats: SystemStats
    /// Modül kapalıysa nil; bağlı aygıt yoksa kart yok.
    let bluetooth: BluetoothMonitor?

    var body: some View {
        // İlk örnek gelince bekleme göstergesinden kartlara çapraz geçiş; sayılar akarak değişir.
        ZStack {
            cards
                .id(stats.snapshot == nil)
                .notchTransition(.swap)
        }
        .notchAnimation(value: stats.snapshot == nil)
        .onAppear { stats.start() }
        .onDisappear { stats.stop() }
    }

    @ViewBuilder
    private var cards: some View {
        Group {
            if let snapshot = stats.snapshot {
                HStack(alignment: .top, spacing: 10) {
                    let cpu = snapshot.cpu ?? 0
                    MetricCard(title: "İşlemci", value: snapshot.cpu == nil ? "–" : NowFormat.percent(cpu * 100),
                               level: cpu, tint: cpu > 0.8 ? .red : .green)
                    let memory = snapshot.memoryTotal > 0 ? Double(snapshot.memoryUsed) / Double(snapshot.memoryTotal) : 0
                    MetricCard(title: "Bellek", value: Self.gigabytes(snapshot.memoryUsed),
                               unit: "/ " + Self.gigabytes(snapshot.memoryTotal) + " GB",
                               level: memory, tint: memory > 0.85 ? .orange : .blue)
                    VStack(alignment: .leading, spacing: NotchDesign.Space.s) {
                        CardLabel("Ağ")
                        rate(SystemStats.formatRate(snapshot.download), symbol: "arrow.down")
                        rate(SystemStats.formatRate(snapshot.upload), symbol: "arrow.up")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .notchCard()
                    if let devices = bluetooth?.devices, !devices.isEmpty {
                        BluetoothCard(devices: devices).notchTransition(.fade)
                    }
                }
                .notchAnimation(value: bluetooth?.devices.map(\.name))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func rate(_ text: String, symbol: String) -> some View {
        HStack(spacing: NotchDesign.Space.xs) {
            Image(systemName: symbol)
                .font(.system(size: NotchDesign.Icon.small, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(verbatim: text).font(NotchDesign.bodyEmphasized.monospacedDigit())
                .contentTransition(.numericText())
        }
    }

    private static func gigabytes(_ bytes: UInt64) -> String {
        (Double(bytes) / 1_073_741_824).formatted(.number.precision(.fractionLength(1)))
    }
}

/// Bağlı Bluetooth aygıtları ve pilleri. Tek aygıtta diğer kartlar gibi büyük yüzde ve çubuk; daha
/// fazlasında en çok iki sıkı satır, kalanı "+N". Sol/sağ/kutu ayrıntısı üzerine gelince.
private struct BluetoothCard: View {
    let devices: [BluetoothMonitor.Device]

    var body: some View {
        if devices.count == 1, let device = devices.first {
            // Başlık aygıtın kendisi (kart dar; "Bluetooth" + ad sığmıyor).
            let level = device.lowest
            VStack(alignment: .leading, spacing: NotchDesign.Space.s) {
                Label {
                    Text(verbatim: device.shortName).lineLimit(1)
                } icon: {
                    Image(systemName: device.symbolName)
                }
                .labelStyle(MetadataLabelStyle())
                .font(NotchDesign.captionEmphasized)
                .foregroundStyle(.secondary)
                Text(verbatim: level.map { NowFormat.percent(Double($0)) } ?? "–")
                    .font(NotchDesign.hero)
                    .contentTransition(.numericText())
                    .notchAnimation(value: level)
                if let level {
                    LevelBar(level: Double(level) / 100, tint: level <= 20 ? .red : .green).frame(height: 4)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .notchCard()
            .help(device.batteryHelp)
        } else {
            VStack(alignment: .leading, spacing: NotchDesign.Space.s) {
                HStack {
                    CardLabel("Bluetooth")
                    Spacer(minLength: NotchDesign.Space.s)
                    if devices.count > 2 {
                        Text(verbatim: "+\(devices.count - 2)").font(NotchDesign.caption).foregroundStyle(NotchDesign.metadata)
                    }
                }
                ForEach(devices.prefix(2)) { device in
                    HStack(spacing: NotchDesign.Space.xs) {
                        Image(systemName: device.symbolName)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 14)
                        Text(verbatim: device.shortName).font(NotchDesign.caption).lineLimit(1)
                        Spacer(minLength: NotchDesign.Space.xxs)
                        if let level = device.lowest {
                            Text(verbatim: NowFormat.percent(Double(level)))
                                .font(NotchDesign.captionEmphasized.monospacedDigit())
                                .foregroundStyle(level <= 20 ? .red : .primary)
                                .contentTransition(.numericText())
                        }
                    }
                    .help(device.batteryHelp)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .notchCard()
        }
    }
}
