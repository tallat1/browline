import Foundation

/// Uygulama paketine gömülü mediaremote-adapter dosyaları (BSD-3, ungive).
/// Çerçeve uygulamaya bağlanmaz; `/usr/bin/perl` yükler. Perl'in bundle kimliği `com.apple.`
/// ile başladığı için mediaremoted ona yanıt veriyor (macOS 15.4 kısıtının geçici çözümü).
public struct MediaRemoteAdapterBundle: Equatable, Sendable {
    public let script: URL
    public let framework: URL
    public let testClient: URL?

    static let perl = URL(fileURLWithPath: "/usr/bin/perl")

    public static func locate(in bundle: Bundle = .main) -> MediaRemoteAdapterBundle? {
        guard let script = bundle.url(forResource: "mediaremote-adapter", withExtension: "pl"),
              let frameworks = bundle.privateFrameworksURL else { return nil }
        let framework = frameworks.appendingPathComponent("MediaRemoteAdapter.framework")
        guard FileManager.default.fileExists(atPath: framework.path) else { return nil }
        let helper = bundle.bundleURL.appendingPathComponent("Contents/Helpers/MediaRemoteAdapterTestClient")
        return MediaRemoteAdapterBundle(
            script: script, framework: framework,
            testClient: FileManager.default.isExecutableFile(atPath: helper.path) ? helper : nil)
    }

    /// Adaptör belgesine göre test istemcisi her komutta çerçeveden sonra verilebilir.
    func arguments(_ command: [String]) -> [String] {
        [script.path, framework.path] + (testClient.map { [$0.path] } ?? []) + command
    }

    /// `test`: çıkış kodu 0 ise adaptör bu macOS sürümünde çalışıyor. Yaklaşık 0,5 sn sürer.
    public func runTest() async -> Bool {
        guard testClient != nil else { return false }
        return await Self.run(arguments(["test"]), timeout: .seconds(8)) == 0
    }

    /// Oynat/duraklat, sonraki, önceki… Kimlikler adaptör belgesindeki tablodan.
    public func send(_ command: Command) {
        Task.detached { _ = await Self.run(arguments(["send", String(command.rawValue)]), timeout: .seconds(4)) }
    }

    public func seek(to seconds: TimeInterval) {
        let micros = String(Int64(max(0, seconds) * 1_000_000))
        Task.detached { _ = await Self.run(arguments(["seek", micros]), timeout: .seconds(4)) }
    }

    public enum Command: Int, Sendable {
        case play = 0, pause = 1, togglePlayPause = 2, nextTrack = 4, previousTrack = 5
    }

    static func run(_ arguments: [String], timeout: Duration) async -> Int32? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Int32?, Never>) in
            let process = Process()
            process.executableURL = perl
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: nil)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout.timeInterval) {
                if process.isRunning { process.terminate() }
            }
        }
    }
}

/// Uzun yaşayan `stream` süreci. Satırları arka planda çözer, yalnız değişen sonucu iletir.
final class AdapterStream: @unchecked Sendable {
    private let process = Process()
    private let lock = NSLock()
    private var stoppedByUs = false

    init(bundle: MediaRemoteAdapterBundle) {
        process.executableURL = MediaRemoteAdapterBundle.perl
        // --debounce: parça değişimindeki küçük güncelleme patlamalarını birleştirir.
        process.arguments = bundle.arguments(["stream", "--micros", "--debounce=80"])
    }

    func start(onUpdate: @escaping @Sendable (AdapterStreamParser.Update) -> Void,
               onExit: @escaping @Sendable (_ status: Int32, _ stoppedByUs: Bool) -> Void) throws {
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] process in
            onExit(process.terminationStatus, self?.wasStoppedByUs ?? true)
        }
        try process.run()
        let handle = output.fileHandleForReading
        Task.detached(priority: .utility) {
            var parser = AdapterStreamParser()
            do {
                for try await line in handle.bytes.lines {
                    if let update = parser.consume(line: line) { onUpdate(update) }
                }
            } catch {
                // Boru kapandı; çıkış terminationHandler'dan raporlanır.
            }
        }
    }

    func stop() {
        lock.withLock { stoppedByUs = true }
        if process.isRunning { process.terminate() }
    }

    private var wasStoppedByUs: Bool { lock.withLock { stoppedByUs } }
}

extension Duration {
    var timeInterval: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}
