import Integrations
import SwiftUI

/// İşlemci, bellek, ağ. Örnekleme yalnız sekme ekrandayken (saniyede bir).
struct SystemTab: View {
    let stats: SystemStats

    var body: some View {
        Group {
            if let snapshot = stats.snapshot {
                HStack(alignment: .top, spacing: 24) {
                    gauge(title: "İşlemci", value: snapshot.cpu, tint: snapshot.cpu > 0.8 ? .red : .green,
                          detail: Text("%\(Int((snapshot.cpu * 100).rounded()))"))
                    let memory = snapshot.memoryTotal > 0 ? Double(snapshot.memoryUsed) / Double(snapshot.memoryTotal) : 0
                    gauge(title: "Bellek", value: memory, tint: memory > 0.85 ? .orange : .blue,
                          detail: Text(verbatim: Self.gigabytes(snapshot.memoryUsed) + " / " + Self.gigabytes(snapshot.memoryTotal) + " GB"))
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Ağ").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        Label(SystemStats.formatRate(snapshot.download), systemImage: "arrow.down")
                        Label(SystemStats.formatRate(snapshot.upload), systemImage: "arrow.up")
                    }
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { stats.start() }
        .onDisappear { stats.stop() }
    }

    private func gauge(title: LocalizedStringKey, value: Double, tint: Color, detail: Text) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            detail
                .font(.system(size: 20, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            LevelBar(level: value, tint: tint).frame(height: 5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func gigabytes(_ bytes: UInt64) -> String {
        (Double(bytes) / 1_073_741_824).formatted(.number.precision(.fractionLength(1)))
    }
}
