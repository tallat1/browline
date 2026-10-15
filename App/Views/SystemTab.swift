import Integrations
import NotchShell
import SwiftUI

/// İşlemci, bellek, ağ. Örnekleme yalnız sekme ekrandayken (saniyede bir).
struct SystemTab: View {
    let stats: SystemStats

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
                    gauge(title: "İşlemci", value: cpu, tint: cpu > 0.8 ? .red : .green,
                          detail: snapshot.cpu == nil ? Text(verbatim: "–") : Text("%\(Int((cpu * 100).rounded()))"))
                    let memory = snapshot.memoryTotal > 0 ? Double(snapshot.memoryUsed) / Double(snapshot.memoryTotal) : 0
                    gauge(title: "Bellek", value: memory, tint: memory > 0.85 ? .orange : .blue,
                          detail: Text(verbatim: Self.gigabytes(snapshot.memoryUsed) + " / " + Self.gigabytes(snapshot.memoryTotal) + " GB"))
                    VStack(alignment: .leading, spacing: 6) {
                        CardLabel("Ağ")
                        Label(SystemStats.formatRate(snapshot.download), systemImage: "arrow.down")
                        Label(SystemStats.formatRate(snapshot.upload), systemImage: "arrow.up")
                    }
                    .font(NotchDesign.bodyEmphasized.monospacedDigit())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .notchCard()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func gauge(title: LocalizedStringKey, value: Double, tint: Color, detail: Text) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            CardLabel(title)
            detail
                .font(.system(size: 20, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
                .notchAnimation(value: value)
            LevelBar(level: value, tint: tint).frame(height: 5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .notchCard()
    }

    private static func gigabytes(_ bytes: UInt64) -> String {
        (Double(bytes) / 1_073_741_824).formatted(.number.precision(.fractionLength(1)))
    }
}
