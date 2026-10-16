import Charts
import Integrations
import NotchShell
import SwiftUI

/// İşlemci, bellek, ağ: son 10 dakikanın grafiği (modül açıkken arka planda 5 sn'de bir, sayfa açıkken
/// saniyede bir örneklenir). Grafiğin üzerine gelince o anın değeri ve saati başlıkta görünür.
struct SystemPage: View {
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
        .onAppear { stats.setForeground(true) }
        .onDisappear { stats.setForeground(false) }
    }

    @ViewBuilder
    private var cards: some View {
        if let snapshot = stats.snapshot {
            // Çizim seyreltilmiş geçmişle (en çok 120 nokta): saniyede bir dört grafik ucuz kalsın.
            let history = SystemStats.downsampled(stats.history)
            HStack(alignment: .top, spacing: 10) {
                CPUCard(snapshot: snapshot, history: history)
                MemoryCard(snapshot: snapshot, history: history)
                NetworkCard(snapshot: snapshot, history: history)
                if let devices = bluetooth?.devices, !devices.isEmpty {
                    BluetoothCard(devices: devices).notchTransition(.fade)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .notchAnimation(value: bluetooth?.devices.map(\.name))
        } else {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    static func gigabytes(_ bytes: UInt64) -> String {
        (Double(bytes) / 1_073_741_824).formatted(.number.precision(.fractionLength(1)))
    }
}

// MARK: - Kart iskeleti

/// Başlık + büyük değer + grafik + alt satır. Üzerine gelinen noktanın değeri başlıktaki değerin yerine
/// geçer, yanında saati.
private struct ChartCard<Chart: View, Footer: View>: View {
    let title: LocalizedStringKey
    let value: String
    var unit: String?
    let hoverTime: Date?
    @ViewBuilder let chart: Chart
    @ViewBuilder let footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: NotchDesign.Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: NotchDesign.Space.s) {
                Text(title).font(NotchDesign.captionEmphasized).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: NotchDesign.Space.xs)
                if let hoverTime {
                    Text(verbatim: hoverTime.formatted(date: .omitted, time: .standard))
                        .font(NotchDesign.caption.monospacedDigit())
                        .foregroundStyle(NotchDesign.metadata)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: NotchDesign.Space.xs) {
                // Akan rakam animasyonu yok: saniyede bir her kartta birkaç kare daha çizdiriyordu.
                Text(verbatim: value)
                    .font(NotchDesign.hero)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit {
                    Text(verbatim: unit).font(NotchDesign.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            chart.frame(maxHeight: .infinity)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .notchCard(padding: EdgeInsets(top: 10, leading: 12, bottom: 9, trailing: 12))
    }
}

/// Grafiğin üzerinde imleç: en yakın örneği bulur.
private struct HoverOverlay: View {
    let proxy: ChartProxy
    let history: [SystemStats.Sample]
    let onHover: (SystemStats.Sample?) -> Void

    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case let .active(location):
                        guard let frame = proxy.plotFrame else { return }
                        let x = location.x - geometry[frame].origin.x
                        guard let date: Date = proxy.value(atX: x) else { return }
                        onHover(history.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
                    case .ended:
                        onHover(nil)
                    }
                }
        }
    }
}

/// Grafiklerin ortak görünümü: eksen yok, ince taban çizgisi, zaman ekseni geçmişin başından şimdiye.
private extension View {
    func sparklineStyle(history: [SystemStats.Sample]) -> some View {
        let end = history.last?.date ?? .now
        let start = min(history.first?.date ?? end.addingTimeInterval(-60), end.addingTimeInterval(-30))
        return self
            .chartXScale(domain: start...end)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .chartPlotStyle { plot in
                plot.overlay(alignment: .bottom) { Rectangle().fill(NotchDesign.hairline).frame(height: 0.5) }
            }
    }
}

private struct LegendDot: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(verbatim: text).lineLimit(1)
        }
        .font(NotchDesign.caption.monospacedDigit())
        .foregroundStyle(NotchDesign.metadata)
    }
}

// MARK: - İşlemci

private struct CPUCard: View {
    let snapshot: SystemStats.Snapshot
    let history: [SystemStats.Sample]
    @State private var hovered: SystemStats.Sample?

    private static let user = Color.green
    private static let system = Color.orange

    var body: some View {
        let user = hovered?.cpuUser ?? snapshot.cpuUser ?? 0
        let system = hovered?.cpuSystem ?? snapshot.cpuSystem ?? 0
        let total = hovered.map { $0.cpuUser + $0.cpuSystem } ?? snapshot.cpu
        ChartCard(title: "İşlemci", value: total.map { NowFormat.percent($0 * 100) } ?? "–", hoverTime: hovered?.date) {
            CPUChart(history: history, hoveredDate: hovered?.date) { hovered = $0 }.equatable()
        } footer: {
            HStack(spacing: NotchDesign.Space.s) {
                LegendDot(color: Self.user, text: NowFormat.percent(user * 100))
                LegendDot(color: Self.system, text: NowFormat.percent(system * 100))
            }
            .help(String(localized: "Yeşil: uygulamalar (\(NowFormat.percent(user * 100))) · Turuncu: sistem (\(NowFormat.percent(system * 100)))"))
        }
    }

}

/// Grafikler kendi görünümünde ve `Equatable`: rakamlar saniyede bir değişse de grafik yalnız geçmiş ya da
/// imleç değişince yeniden çizilir. Aynı karttayken her saniye baştan kuruluyordu (açık Sistem sayfası
/// %2,8 işlemci, 2026-10-16 ölçümü).
private struct CPUChart: View, Equatable {
    let history: [SystemStats.Sample]
    let hoveredDate: Date?
    let onHover: (SystemStats.Sample?) -> Void

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.history == rhs.history && lhs.hoveredDate == rhs.hoveredDate }

    var body: some View {
        Chart {
            ForEach(history) { sample in
                AreaMark(x: .value("Zaman", sample.date), y: .value("Pay", sample.cpuUser))
                    .foregroundStyle(by: .value("Tür", "user"))
                AreaMark(x: .value("Zaman", sample.date), y: .value("Pay", sample.cpuSystem))
                    .foregroundStyle(by: .value("Tür", "system"))
            }
            if let hoveredDate {
                RuleMark(x: .value("Zaman", hoveredDate)).foregroundStyle(.white.opacity(0.35))
            }
        }
        .chartForegroundStyleScale(["user": Color.green.opacity(0.75), "system": Color.orange.opacity(0.85)])
        // Düşük kullanımda grafik düz kalmasın: üst sınır %25'lik adımlarla; büyük rakam gerçek değer.
        .chartYScale(domain: 0...Self.upperBound(history))
        .sparklineStyle(history: history)
        .chartOverlay { HoverOverlay(proxy: $0, history: history, onHover: onHover) }
    }

    static func upperBound(_ history: [SystemStats.Sample]) -> Double {
        let peak = history.map { $0.cpuUser + $0.cpuSystem }.max() ?? 0
        return min(1, max(0.25, (peak * 4).rounded(.up) / 4))
    }
}

// MARK: - Bellek

private struct MemoryCard: View {
    let snapshot: SystemStats.Snapshot
    let history: [SystemStats.Sample]
    @State private var hovered: SystemStats.Sample?

    var body: some View {
        let total = Double(snapshot.memoryTotal)
        let used = hovered.map { UInt64($0.memory * total) } ?? snapshot.memoryUsed
        ChartCard(title: "Bellek", value: SystemPage.gigabytes(used),
                  unit: "/ " + SystemPage.gigabytes(snapshot.memoryTotal) + " GB", hoverTime: hovered?.date) {
            MemoryChart(history: history, hoveredDate: hovered?.date) { hovered = $0 }.equatable()
        } footer: {
            if let memory = snapshot.memory {
                MemoryBreakdownBar(memory: memory, total: snapshot.memoryTotal)
            }
        }
    }
}

private struct MemoryChart: View, Equatable {
    let history: [SystemStats.Sample]
    let hoveredDate: Date?
    let onHover: (SystemStats.Sample?) -> Void

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.history == rhs.history && lhs.hoveredDate == rhs.hoveredDate }

    var body: some View {
        Chart {
            ForEach(history) { sample in
                AreaMark(x: .value("Zaman", sample.date), y: .value("Oran", sample.memory))
                    .foregroundStyle(LinearGradient(colors: [.blue.opacity(0.55), .blue.opacity(0.12)],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Zaman", sample.date), y: .value("Oran", sample.memory))
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 1.2))
            }
            if let hoveredDate {
                RuleMark(x: .value("Zaman", hoveredDate)).foregroundStyle(.white.opacity(0.35))
            }
        }
        .chartYScale(domain: 0...1)
        .sparklineStyle(history: history)
        .chartOverlay { HoverOverlay(proxy: $0, history: history, onHover: onHover) }
    }
}

/// Uygulama, kablolu ve sıkıştırılmış bellek orantılı tek çubukta; ayrıntı üzerine gelince.
private struct MemoryBreakdownBar: View {
    let memory: SystemStats.MemoryBreakdown
    let total: UInt64

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let scale = total > 0 ? width / CGFloat(total) : 0
            HStack(spacing: 1) {
                Capsule().fill(Color.blue).frame(width: max(2, CGFloat(memory.app) * scale))
                Capsule().fill(Color.orange).frame(width: max(2, CGFloat(memory.wired) * scale))
                Capsule().fill(Color.purple).frame(width: max(2, CGFloat(memory.compressed) * scale))
                Spacer(minLength: 0)
            }
            .background(Capsule().fill(NotchDesign.track))
        }
        .frame(height: 5)
        .padding(.vertical, 4)
        .help(String(localized: "Uygulama \(SystemPage.gigabytes(memory.app)) GB · Kablolu \(SystemPage.gigabytes(memory.wired)) GB · Sıkıştırılmış \(SystemPage.gigabytes(memory.compressed)) GB"))
    }
}

// MARK: - Ağ

private struct NetworkCard: View {
    let snapshot: SystemStats.Snapshot
    let history: [SystemStats.Sample]
    @State private var hovered: SystemStats.Sample?

    private static let download = Color.cyan
    private static let upload = Color.pink

    var body: some View {
        let down = hovered?.download ?? snapshot.download
        let up = hovered?.upload ?? snapshot.upload
        let peak = history.map(\.download).max() ?? 0
        ChartCard(title: "Ağ", value: SystemStats.formatRate(down), hoverTime: hovered?.date) {
            NetworkChart(history: history, hoveredDate: hovered?.date) { hovered = $0 }.equatable()
        } footer: {
            // Büyük rakam indirme; altta yalnız yükleme (dar kartta ikisi sığmıyordu).
            HStack(spacing: NotchDesign.Space.s) {
                LegendDot(color: Self.download, text: "↓")
                LegendDot(color: Self.upload, text: "↑ " + SystemStats.formatRate(up))
            }
            .help(String(localized: "Son 10 dakikada en yüksek indirme: \(SystemStats.formatRate(peak))"))
        }
    }
}

private struct NetworkChart: View, Equatable {
    let history: [SystemStats.Sample]
    let hoveredDate: Date?
    let onHover: (SystemStats.Sample?) -> Void

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.history == rhs.history && lhs.hoveredDate == rhs.hoveredDate }

    var body: some View {
        let peak = max(history.map(\.download).max() ?? 0, history.map(\.upload).max() ?? 0, 1024)
        Chart {
            ForEach(history) { sample in
                LineMark(x: .value("Zaman", sample.date), y: .value("Hız", sample.download), series: .value("Yön", "down"))
                    .foregroundStyle(Color.cyan)
                    .lineStyle(StrokeStyle(lineWidth: 1.4))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Zaman", sample.date), y: .value("Hız", sample.upload), series: .value("Yön", "up"))
                    .foregroundStyle(Color.pink)
                    .lineStyle(StrokeStyle(lineWidth: 1.4))
                    .interpolationMethod(.monotone)
            }
            if let hoveredDate {
                RuleMark(x: .value("Zaman", hoveredDate)).foregroundStyle(.white.opacity(0.35))
            }
        }
        .chartYScale(domain: 0...peak)
        .sparklineStyle(history: history)
        .chartOverlay { HoverOverlay(proxy: $0, history: history, onHover: onHover) }
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
                Spacer(minLength: 0)
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
