import Darwin
import Foundation
import Observation

/// İşlemci, bellek ve ağ hızı. Public Mach ve getifaddrs; yalnız sekme ekrandayken saniyede bir
/// örneklenir, sekme kapanınca durur.
@MainActor
@Observable
public final class SystemStats {
    public struct Snapshot: Equatable, Sendable {
        /// 0…1; ilk örnekte (iki sayaç okuması gerekir) nil.
        public var cpu: Double?
        public var memoryUsed: UInt64
        public var memoryTotal: UInt64
        /// Bayt/sn
        public var download: Double
        public var upload: Double
    }

    public private(set) var snapshot: Snapshot?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var lastTicks: CPUTicks?
    @ObservationIgnored private var lastBytes: (received: UInt64, sent: UInt64, at: Date)?

    public init() {}

    public func start() {
        guard task == nil else { return }
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.sample()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        lastTicks = nil
        lastBytes = nil
    }

    // MARK: - Örnekleme

    struct CPUTicks: Equatable {
        var busy: UInt64
        var total: UInt64
    }

    /// İki örnek arası meşgul oranı; ilk örnekte ya da sayaç geri gittiyse nil.
    nonisolated static func cpuUsage(from old: CPUTicks?, to new: CPUTicks) -> Double? {
        guard let old, new.total > old.total, new.busy >= old.busy else { return nil }
        return min(1, Double(new.busy - old.busy) / Double(new.total - old.total))
    }

    private func sample() {
        let ticks = Self.readCPUTicks()
        let cpu = ticks.flatMap { Self.cpuUsage(from: lastTicks, to: $0) }
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
        snapshot = Snapshot(cpu: cpu, memoryUsed: Self.readMemoryUsed() ?? 0,
                            memoryTotal: ProcessInfo.processInfo.physicalMemory,
                            download: download, upload: upload)
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
        return CPUTicks(busy: user + system + nice, total: user + system + idle + nice)
    }

    /// Etkinlik Monitörü'ndeki "Kullanılan Bellek"e yakın: uygulama belleği + kablolu + sıkıştırılmış.
    private static func readMemoryUsed() -> UInt64? {
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
        let pages = appPages + UInt64(info.wire_count) + UInt64(info.compressor_page_count)
        return pages * UInt64(pageSize)
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
