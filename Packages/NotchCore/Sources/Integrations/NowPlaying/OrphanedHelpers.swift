import Darwin
import Foundation

/// Süreç tablosundan bir satır: yetim yardımcı kararı için gereken kadarı.
public struct ProcessEntry: Equatable, Sendable {
    public let pid: Int32
    public let parentPID: Int32
    public let userID: UInt32
    /// `execve`'ye verilen yol (`KERN_PROCARGS2`); okunamadıysa nil.
    public let executable: String?
    public let arguments: [String]

    public init(pid: Int32, parentPID: Int32, userID: UInt32, executable: String?, arguments: [String]) {
        self.pid = pid
        self.parentPID = parentPID
        self.userID = userID
        self.executable = executable
        self.arguments = arguments
    }
}

/// Uygulama `kill -9` ya da çökmeyle bittiğinde Now Playing yardımcıları (`/usr/bin/perl <betik> …`)
/// ebeveyni 1 (launchd) olan yetimler olarak çalışmayı sürdürür; `applicationWillTerminate` hiç çalışmaz.
/// Açılışta yalnız BU paketin betiklerini çalıştıran, bu kullanıcının yetimleri kapatılır. Başka bir kopyanın
/// (başka yol) ya da çalışan bir uygulamanın (ebeveyni 1 değil) yardımcısına dokunulmaz.
public enum OrphanedHelpers {
    static let perl = MediaRemoteAdapterBundle.perl.path
    static let scripts = [("mediaremote-adapter", "pl"), ("media-sessions", "pl")]

    /// Başlatırken kullanılan `Bundle.url(forResource:)` ile aynı yol: eşleşme dize düzeyinde tam.
    public static func scriptPaths(in bundle: Bundle) -> Set<String> {
        Set(scripts.compactMap { bundle.url(forResource: $0.0, withExtension: $0.1)?.path })
    }

    /// Saf karar: ebeveyni 1, sahibi `userID`, `/usr/bin/perl` ile çalışan ve ilk argümanı (betik) bu
    /// paketin betiklerinden biriyle birebir aynı süreçler.
    public static func select(from processes: [ProcessEntry], scriptPaths: Set<String>, userID: UInt32) -> [Int32] {
        processes.filter { process in
            process.pid > 1 && process.parentPID == 1 && process.userID == userID
                && process.executable == perl
                && process.arguments.count >= 2 && scriptPaths.contains(process.arguments[1])
        }.map(\.pid)
    }

    /// Süreç tablosunu okur, seçilenlere SIGTERM gönderir; gönderilebilenleri döndürür.
    @discardableResult
    public static func terminate(in bundle: Bundle = .main) -> [Int32] {
        let paths = scriptPaths(in: bundle)
        guard !paths.isEmpty else { return [] }
        let userID = getuid()
        // Argüman okumak (sysctl) yalnız yetim ve bize ait adaylar için; karar yine select'te.
        let candidates = ProcessTable.entries { $0.parentPID == 1 && $0.userID == userID }
        let selected = select(from: candidates, scriptPaths: paths, userID: userID)
        let terminated = selected.filter { kill($0, SIGTERM) == 0 }
        if !terminated.isEmpty {
            let pids = terminated.map(String.init).joined(separator: ", ")
            Log.integrations.notice("Önceki çalışmadan kalan \(terminated.count) Now Playing yardımcısı kapatıldı (pid \(pids, privacy: .public))")
        }
        return terminated
    }
}

/// libproc + sysctl ile süreç tablosu. Yalnız aynı kullanıcının süreçlerinin argümanları okunabilir.
enum ProcessTable {
    struct Basic { let pid: Int32; let parentPID: Int32; let userID: UInt32 }

    /// `include` ucuz alanlara (ebeveyn, sahip) bakar; argümanlar yalnız geçenler için okunur.
    static func entries(where include: (Basic) -> Bool) -> [ProcessEntry] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        // Çağrılar arasında yeni süreç doğabilir: pay bırakılır.
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard count > 0 else { return [] }
        return pids.prefix(Int(count)).compactMap { pid in
            guard let basic = basic(pid), include(basic) else { return nil }
            let command = arguments(pid)
            return ProcessEntry(pid: pid, parentPID: basic.parentPID, userID: basic.userID,
                                executable: command?.executable, arguments: command?.arguments ?? [])
        }
    }

    static func basic(_ pid: pid_t) -> Basic? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Basic(pid: pid, parentPID: Int32(info.pbi_ppid), userID: info.pbi_uid)
    }

    static func arguments(_ pid: pid_t) -> (executable: String, arguments: [String])? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        return parseProcArgs(Array(buffer.prefix(size)))
    }

    /// `KERN_PROCARGS2` düzeni: 4 bayt argc, NUL'la biten exec yolu, hizalama NUL'ları, argc tane
    /// NUL'la biten argüman, ardından ortam değişkenleri (okunmaz).
    static func parseProcArgs(_ bytes: [UInt8]) -> (executable: String, arguments: [String])? {
        guard bytes.count > MemoryLayout<Int32>.size else { return nil }
        let argc = bytes.withUnsafeBytes { Int($0.loadUnaligned(as: Int32.self)) }
        guard argc >= 0 else { return nil }
        var index = MemoryLayout<Int32>.size
        func nextString() -> String? {
            guard index < bytes.count, let end = bytes[index...].firstIndex(of: 0) else { return nil }
            defer { index = end + 1 }
            return String(decoding: bytes[index..<end], as: UTF8.self)
        }
        guard let executable = nextString() else { return nil }
        while index < bytes.count, bytes[index] == 0 { index += 1 }
        var arguments: [String] = []
        for _ in 0..<argc {
            guard let argument = nextString() else { return nil }
            arguments.append(argument)
        }
        return (executable, arguments)
    }
}
