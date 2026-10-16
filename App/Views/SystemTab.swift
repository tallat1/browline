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
                }
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
