import Darwin
import Foundation

/// Çalışan Claude masaüstü örnekleri. Birden çok hesap aynı uygulamayı ayrı veri klasörüyle (`--user-data-dir`)
/// aynı anda çalıştırabiliyor; uygulama kimliği aynı olduğu için `claude://` bağlantısını macOS hep EN ESKİ örneğe
/// veriyor (2026-10-17: bu hesabın Claude'u öndeyken bile diğer hesabın penceresi öne geldi). Oturumun sahibi,
/// oturum dosyasının (`<veri klasörü>/claude-code-sessions/**/local_….json`) bulunduğu örnek.
public enum ClaudeDesktop {
    public struct Instance: Equatable, Sendable {
        public var pid: pid_t
        public var dataDirectory: URL
    }

    public static var defaultDataDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Claude", isDirectory: true)
    }

    /// Ana süreçler (`Claude.app/Contents/MacOS/Claude`), yardımcılar değil.
    public static func instances() -> [Instance] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) * 2)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        return pids.prefix(Int(max(0, filled))).compactMap { pid -> Instance? in
            guard pid > 0, let path = executablePath(pid), path.hasSuffix(".app/Contents/MacOS/Claude") else { return nil }
            let directory = processArguments(pid).flatMap(dataDirectory(fromArguments:)) ?? defaultDataDirectory
            return Instance(pid: pid, dataDirectory: directory)
        }
    }

    /// Masaüstü oturumunu (`local_…`) açmış örnek; oturum dosyası onun veri klasöründe.
    public static func owner(ofDesktopSession session: String, among instances: [Instance] = instances()) -> Instance? {
        instances.first { instance in
            sessionFiles(in: instance.dataDirectory).contains { $0.deletingPathExtension().lastPathComponent == session }
        }
    }

    /// Bağlantıyı belirli örneğe Apple Event (`GURL`) olarak gönderir; `open` bunu yapamaz (hep en eski örnek). İlk
    /// seferde macOS "Browline, Claude'u denetlemek istiyor" diye sorar; izin yoksa false.
    public static func open(_ url: URL, in instance: Instance) -> Bool {
        let gurl: FourCharCode = 0x4755_524C // 'GURL': kInternetEventClass ve kAEGetURL
        let event = NSAppleEventDescriptor.appleEvent(
            withEventClass: gurl, eventID: gurl, targetDescriptor: NSAppleEventDescriptor(processIdentifier: instance.pid),
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(NSAppleEventDescriptor(string: url.absoluteString), forKeyword: AEKeyword(keyDirectObject))
        return (try? event.sendEvent(options: .noReply, timeout: 10)) != nil
    }

    /// Oturum dosyalarının arandığı kökler: varsayılan klasör ve çalışan her örneğin klasörü.
    public static func sessionRoots(among instances: [Instance] = instances()) -> [URL] {
        var seen = Set<String>()
        return ([defaultDataDirectory] + instances.map(\.dataDirectory))
            .map { $0.appendingPathComponent("claude-code-sessions", isDirectory: true) }
            .filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    static func sessionFiles(in dataDirectory: URL) -> [URL] {
        let root = dataDirectory.appendingPathComponent("claude-code-sessions", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil,
                                                              options: [.skipsHiddenFiles]) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { $0.lastPathComponent.hasPrefix("local_") && $0.pathExtension == "json" }
    }

    /// `--user-data-dir=/yol` ya da `--user-data-dir /yol`.
    static func dataDirectory(fromArguments arguments: [String]) -> URL? {
        for (index, argument) in arguments.enumerated() {
            if argument.hasPrefix("--user-data-dir=") {
                return URL(fileURLWithPath: String(argument.dropFirst("--user-data-dir=".count)), isDirectory: true)
            }
            if argument == "--user-data-dir", arguments.indices.contains(index + 1) {
                return URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
            }
        }
        return nil
    }

    private static func executablePath(_ pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
    }

    /// `KERN_PROCARGS2`: argc, çalıştırılabilir yol, boşluk, sonra argv. Aynı kullanıcının süreçleri okunabilir.
    static func processArguments(_ pid: pid_t) -> [String]? {
        var maximum: Int32 = 0
        var size = MemoryLayout<Int32>.size
        var argmax = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&argmax, 2, &maximum, &size, nil, 0) == 0, maximum > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: Int(maximum))
        var length = buffer.count
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        guard sysctl(&mib, 3, &buffer, &length, nil, 0) == 0, length > MemoryLayout<Int32>.size else { return nil }
        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        var index = MemoryLayout<Int32>.size
        while index < length, buffer[index] != 0 { index += 1 }
        while index < length, buffer[index] == 0 { index += 1 }
        var arguments: [String] = []
        while arguments.count < argc, index < length {
            let start = index
            while index < length, buffer[index] != 0 { index += 1 }
            arguments.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return arguments
    }
}
