import Darwin
import Foundation
import Observation

/// İşlemci, bellek ve ağ hızı. Public Mach ve getifaddrs. Sayfa ekrandayken saniyede bir; modül
/// açıkken arka planda 5 sn'de bir (2 sn esneklikle, uyanmalar birleşsin) örneklenir ve son 10 dakika
/// grafik için tutulur: kullanıcı "daha ayrıntılı grafik" istedi (2026-10-16), sayfa açılınca geçmiş
/// hazır olsun.
@MainActor
@Observable
public final class SystemStats {
    public struct Snapshot: Equatable, Sendable {
        /// 0…1; ilk örnekte (iki sayaç okuması gerekir) nil.
        public var cpu: Double?
        /// İşlemcinin kullanıcı (uygulamalar) ve sistem (çekirdek) payı, 0…1.
        public var cpuUser: Double?
        public var cpuSystem: Double?
        public var memoryUsed: UInt64
        public var memoryTotal: UInt64
        public var memory: MemoryBreakdown?
        /// Bayt/sn
        public var download: Double
        public var upload: Double
    }

    /// Etkinlik Monitörü'nün bellek ayrımı (bayt).
    public struct MemoryBreakdown: Equatable, Sendable {
        public var app: UInt64
        public var wired: UInt64
        public var compressed: UInt64
        public var used: UInt64 { app + wired + compressed }
    }

    /// Grafik noktası.
    public struct Sample: Identifiable, Equatable, Sendable {
        public var id: Date { date }
        public let date: Date
        public let cpuUser: Double
        public let cpuSystem: Double
        /// Kullanılan bellek oranı, 0…1.
        public let memory: Double
        public let download: Double
        public let upload: Double
    }

    public private(set) var snapshot: Snapshot?
    public private(set) var history: [Sample] = []
    public nonisolated static let historyWindow: TimeInterval = 600
    nonisolated static let minimumHistorySpacing: TimeInterval = 1.9
    @ObservationIgnored private var isEnabled = false
    @ObservationIgnored private var isForeground = false
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var lastTicks: CPUTicks?
    @ObservationIgnored private var lastBytes: (received: UInt64, sent: UInt64, at: Date)?

    public init() {}

    /// Modül açıkken: arka planda seyrek örnekleme, geçmiş birikir.
    public func startBackground() {
        guard !isEnabled else { return }
        isEnabled = true
        restart()
    }

    /// Sayfa görünür olunca saniyede bir; kapanınca arka plan hızına (modül kapalıysa durur).
    public func setForeground(_ foreground: Bool) {
        guard foreground != isForeground else { return }
        isForeground = foreground
        restart()
    }

    public func stop() {
        isEnabled = false
        isForeground = false
        task?.cancel()
        task = nil
        lastTicks = nil
        lastBytes = nil
        history = []
        snapshot = nil
    }

    private func restart() {
        task?.cancel()
        task = nil
        guard isEnabled || isForeground else {
            lastTicks = nil
            lastBytes = nil
            return
        }
        let foreground = isForeground
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.sample()
                if foreground {
                    try? await Task.sleep(for: .seconds(1), tolerance: .milliseconds(100))
                } else {
                    try? await Task.sleep(for: .seconds(5), tolerance: .seconds(2))
                }
            }
        }
    }

    /// Çizim için en çok `limit` nokta: eşit aralıklı seçilir, son nokta hep kalır. Saniyelik örneklerle
    /// 10 dakika 600 nokta ediyordu; dört grafiği her saniye çizmek açık Sistem sayfasında %2,35 işlemci
    /// tutuyordu (2026-10-16 ölçümü).
    public nonisolated static func downsampled(_ history: [Sample], limit: Int = 120) -> [Sample] {
        guard history.count > limit, limit > 1 else { return history }
        let step = Double(history.count - 1) / Double(limit - 1)
        return (0..<limit).map { history[Int((Double($0) * step).rounded())] }
    }

    /// Ölçüm için: geçmişi son 10 dakikanın saniyelik yapay noktalarıyla doldurur (çizim maliyeti).
    public func fillHistoryForMeasurement(now: Date = .now) {
        history = (0..<600).map { index in
            let t = Double(index)
            return Sample(date: now.addingTimeInterval(t - 600), cpuUser: 0.1 + 0.05 * sin(t / 9),
                          cpuSystem: 0.05, memory: 0.8, download: 2_000 + 1_500 * sin(t / 5), upload: 800)
        }
    }

    /// Pencere dışına düşenler atılır.
    nonisolated static func trimmed(_ history: [Sample], now: Date) -> [Sample] {
        let cutoff = now.addingTimeInterval(-historyWindow)
        guard let first = history.firstIndex(where: { $0.date >= cutoff }) else { return [] }
        return first == 0 ? history : Array(history[first...])
    }

    // MARK: - Örnekleme

    struct CPUTicks: Equatable {
        var user: UInt64 = 0
        var system: UInt64 = 0
        var busy: UInt64
        var total: UInt64
    }

    /// İki örnek arası meşgul oranı; ilk örnekte ya da sayaç geri gittiyse nil.
    nonisolated static func cpuUsage(from old: CPUTicks?, to new: CPUTicks) -> Double? {
        guard let old, new.total > old.total, new.busy >= old.busy else { return nil }
        return min(1, Double(new.busy - old.busy) / Double(new.total - old.total))
    }

    /// Kullanıcı (nice dahil) ve sistem payları; toplamları meşgul oranına eşit.
    nonisolated static func cpuSplit(from old: CPUTicks?, to new: CPUTicks) -> (user: Double, system: Double)? {
        guard let old, new.total > old.total, new.user >= old.user, new.system >= old.system else { return nil }
        let total = Double(new.total - old.total)
        return (min(1, Double(new.user - old.user) / total), min(1, Double(new.system - old.system) / total))
    }

    private func sample() {
        let ticks = Self.readCPUTicks()
        let cpu = ticks.flatMap { Self.cpuUsage(from: lastTicks, to: $0) }
        let split = ticks.flatMap { Self.cpuSplit(from: lastTicks, to: $0) }
        lastTicks = ticks
        let now = Date.now
        let bytes = Self.readNetworkBytes()
        var download = 0.0, upload = 0.0
        if let bytes, let last = lastBytes, now > last.at {
            let seconds = now.timeIntervalSince(last.at)
            download = Double(bytes.received &- last.received) / seconds
            upload = Double(bytes.sent &- last.sent) / seconds
            // Arayüz yeniden başlayınca sayaç sıfırlanabilir; anlamsız sıçramayı gösterme.
            if bytes.received < last.received { download = 0 }
            if bytes.sent < last.sent { upload = 0 }
        }
        if let bytes { lastBytes = (bytes.received, bytes.sent, now) }
        // Bellek ilk örnekte de gösterilir; işlemci bir saniye sonra gelir.
        let memory = Self.readMemory()
        let total = ProcessInfo.processInfo.physicalMemory
        snapshot = Snapshot(cpu: cpu, cpuUser: split?.user, cpuSystem: split?.system,
                            memoryUsed: memory?.used ?? 0, memoryTotal: total, memory: memory,
                            download: download, upload: upload)
        // İlk örnekte işlemci payı yok (iki sayaç okuması gerekir): geçmişe ikinci örnekten itibaren.
        // Grafik en sık 2 sn'de bir değişir (rakamlar saniyede bir): dört grafiği her saniye yeniden
        // çizmek açık sayfada belirgin işlemci tutuyordu.
        if let split, now.timeIntervalSince(history.last?.date ?? .distantPast) >= Self.minimumHistorySpacing {
            let point = Sample(date: now, cpuUser: split.user, cpuSystem: split.system,
                               memory: total > 0 ? Double(memory?.used ?? 0) / Double(total) : 0,
                               download: download, upload: upload)
            history = Self.trimmed(history + [point], now: now)
        }
    }

    private static func readCPUTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        return CPUTicks(user: user + nice, system: system, busy: user + system + nice, total: user + system + idle + nice)
    }

    /// Etkinlik Monitörü'ndeki "Kullanılan Bellek"e yakın: uygulama belleği + kablolu + sıkıştırılmış.
    private static func readMemory() -> MemoryBreakdown? {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        var pageSize: vm_size_t = 0
        guard result == KERN_SUCCESS, host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return nil }
        let appPages = UInt64(info.internal_page_count) - min(UInt64(info.purgeable_count), UInt64(info.internal_page_count))
        let size = UInt64(pageSize)
        return MemoryBreakdown(app: appPages * size, wired: UInt64(info.wire_count) * size,
                               compressed: UInt64(info.compressor_page_count) * size)
    }

    /// Geri döngü dışındaki arayüzlerin toplam bayt sayaçları.
    private static func readNetworkBytes() -> (received: UInt64, sent: UInt64)? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return nil }
        defer { freeifaddrs(addresses) }
        var received: UInt64 = 0, sent: UInt64 = 0
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
                  entry.ifa_flags & UInt32(IFF_LOOPBACK) == 0, entry.ifa_flags & UInt32(IFF_UP) != 0,
                  let data = entry.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
            received += UInt64(data.pointee.ifi_ibytes)
            sent += UInt64(data.pointee.ifi_obytes)
        }
        return (received, sent)
    }

    /// 1536 → "1,5 KB/sn" (yerel biçim).
    public nonisolated static func formatRate(_ bytesPerSecond: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond.rounded()), countStyle: .binary) + "/s"
    }
}
