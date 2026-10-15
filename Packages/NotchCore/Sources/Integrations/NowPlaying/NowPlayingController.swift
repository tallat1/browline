import AppKit
import Observation

/// Katmanlı Now Playing: önce adaptörü `test` ile yoklar; geçerse `stream`, geçmezse oynatıcı
/// bildirimleri. Arayüz hangi kaynağın kullanıldığını gösterir (raporun önerisi).
@MainActor
@Observable
public final class NowPlayingController {
    public enum Source: Equatable, Sendable {
        case checking
        case mediaRemote
        /// Yedek kaynak; neden düşüldüğü kullanıcıya gösterilir.
        case playerNotifications(FallbackReason)
        case off
    }

    /// Metin değil neden: kullanıcıya gösterilecek çeviriyi uygulama yapar.
    public enum FallbackReason: Equatable, Sendable, CustomStringConvertible {
        case adapterMissing
        case adapterTestFailed
        case adapterLaunchFailed
        case adapterExited(Int32)

        public var description: String {
            switch self {
            case .adapterMissing: "adapter-missing"
            case .adapterTestFailed: "adapter-test-failed"
            case .adapterLaunchFailed: "adapter-launch-failed"
            case let .adapterExited(status): "adapter-exited(\(status))"
            }
        }
    }

    public private(set) var info: NowPlayingInfo?
    public private(set) var source: Source = .off
    public private(set) var artwork: NSImage?
    /// Kapak her değiştiğinde artar; görünümler çapraz geçişi buna bağlar.
    public private(set) var artworkVersion = 0
    /// Kapaktan türetilen vurgu rengi; siyah notch üstünde okunacak kadar parlak.
    public private(set) var accentColor: NSColor?

    @ObservationIgnored public var onInfoChanged: ((NowPlayingInfo?) -> Void)?
    @ObservationIgnored private var adapter: MediaRemoteAdapterBundle?
    @ObservationIgnored private var stream: AdapterStream?
    @ObservationIgnored private var restartAttempt = 0
    @ObservationIgnored private let fallback = PlayerNotificationSource()
    @ObservationIgnored private var artworkSource: Data?
    @ObservationIgnored private var generation = 0
    /// Şarkı geçişinde oynatıcılar bir an "çalan yok" bildiriyor; bilgi hemen silinmez.
    @ObservationIgnored private var clearTask: Task<Void, Never>?
    /// Yeni şarkının kapağı başlıktan sonra geliyor; o arada eski kapak korunur (yer tutucu titremesin).
    @ObservationIgnored private var artworkHoldTask: Task<Void, Never>?

    /// Geçiş payı: bu süre içinde yeni bilgi gelirse arayüz hiç boşalmaz.
    static let transitionGrace: Duration = .milliseconds(1500)
    static let artworkHold: Duration = .seconds(2)

    /// Çöken akış için yeniden başlatma aralıkları; sonra yedeğe düşülür.
    private static let restartDelays: [Duration] = [.seconds(2), .seconds(2), .seconds(15), .seconds(60)]

    public init() {}

    public func start() {
        guard source == .off else { return }
        generation += 1
        let current = generation
        guard let bundle = MediaRemoteAdapterBundle.locate() else {
            useFallback(reason: .adapterMissing)
            return
        }
        adapter = bundle
        source = .checking
        Task { @MainActor [weak self] in
            let works = await bundle.runTest()
            guard let self, self.generation == current else { return }
            if works {
                self.startStream()
            } else {
                self.useFallback(reason: .adapterTestFailed)
            }
        }
    }

    public func stop() {
        generation += 1
        stream?.stop()
        stream = nil
        fallback.stop()
        source = .off
        set(info: nil, immediately: true)
    }

    // MARK: - Komutlar

    public func togglePlayPause() { send(.togglePlayPause) }
    public func nextTrack() { send(.nextTrack) }
    public func previousTrack() { send(.previousTrack) }

    /// Yalnız adaptörle; yedek kaynakta konum bilinmiyor.
    public var canSeek: Bool { source == .mediaRemote && info?.duration != nil }

    public func seek(to seconds: TimeInterval) {
        guard source == .mediaRemote, let adapter, var current = info else { return }
        let target = min(max(0, seconds), current.duration ?? seconds)
        if let bundle = current.bundleIdentifier, PlayerNotificationSource.supportsScriptedSeek(bundle) {
            PlayerNotificationSource.seek(to: target, bundleIdentifier: bundle)
            Log.integrations.notice("Medya: konum \(Int(target)) sn (AppleScript, \(bundle, privacy: .public))")
        } else {
            adapter.seek(to: target)
            Log.integrations.notice("Medya: konum \(Int(target)) sn (MediaRemote)")
        }
        // İyimser güncelleme: çubuk akıştan gelecek düzeltmeyi beklemeden yeni konuma atlar.
        current.elapsedTime = target
        current.timestamp = .now
        set(info: current)
    }

    /// İleri ya da geri (saniye). Oynatıcının kendi 15 sn komutu yerine seek: Spotify onu bildirmiyor.
    public func skip(by seconds: TimeInterval) {
        guard let elapsed = info?.elapsed(at: .now) else { return }
        seek(to: elapsed + seconds)
    }

    /// Karıştırma ve tekrar yalnız oynatıcı durumunu bildiriyorsa (Music evet, Spotify hayır).
    public var supportsShuffleAndRepeat: Bool {
        source == .mediaRemote && info?.shuffleMode != nil && info?.repeatMode != nil
    }

    /// Kapalı → parça karıştırma → kapalı.
    public func cycleShuffle() {
        guard source == .mediaRemote, let adapter, let mode = info?.shuffleMode else { return }
        adapter.setShuffle(Self.nextShuffleMode(after: mode))
    }

    nonisolated static func nextShuffleMode(after mode: Int) -> Int { mode == 1 ? 3 : 1 }

    nonisolated static func nextRepeatMode(after mode: Int) -> Int { mode == 1 ? 3 : (mode == 3 ? 2 : 1) }

    /// Kapalı → listeyi tekrarla → parçayı tekrarla → kapalı.
    public func cycleRepeat() {
        guard source == .mediaRemote, let adapter, let mode = info?.repeatMode else { return }
        adapter.setRepeat(Self.nextRepeatMode(after: mode))
    }

    private func send(_ command: MediaRemoteAdapterBundle.Command) {
        switch source {
        case .mediaRemote:
            adapter?.send(command)
        case .playerNotifications:
            if let bundleIdentifier = info?.bundleIdentifier { fallback.send(command, to: bundleIdentifier) }
        case .checking, .off:
            break
        }
    }

    // MARK: - Kaynaklar

    private func startStream() {
        guard let adapter else { return }
        let stream = AdapterStream(bundle: adapter)
        let current = generation
        do {
            try stream.start(
                onUpdate: { [weak self] update in
                    // Sırayı korumak için ana kuyruk; her güncelleme ayrı Task açmaz.
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            guard let self, self.generation == current else { return }
                            switch update {
                            case .nothingPlaying: self.set(info: nil)
                            case let .playing(info): self.set(info: info)
                            }
                        }
                    }
                },
                onExit: { [weak self] status, stoppedByUs in
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            guard let self, !stoppedByUs, self.generation == current else { return }
                            self.streamExited(status: status)
                        }
                    }
                })
            self.stream = stream
            source = .mediaRemote
            Log.integrations.info("Now Playing: mediaremote-adapter akışı başladı")
        } catch {
            useFallback(reason: .adapterLaunchFailed)
        }
    }

    private func streamExited(status: Int32) {
        stream = nil
        // Belge: sıfır dışı çıkış ölümcül hatadır, betik yeniden çağrılmamalı.
        guard status == 0, restartAttempt < Self.restartDelays.count else {
            useFallback(reason: .adapterExited(status))
            return
        }
        let delay = Self.restartDelays[restartAttempt]
        restartAttempt += 1
        let current = generation
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, self.generation == current else { return }
            self.startStream()
        }
    }

    private func useFallback(reason: FallbackReason) {
        stream?.stop()
        stream = nil
        source = .playerNotifications(reason)
        Log.integrations.notice("Now Playing yedeğe düştü: \(reason.description, privacy: .public)")
        fallback.onUpdate = { [weak self] info in self?.set(info: info) }
        fallback.start()
    }

    private func set(info newValue: NowPlayingInfo?, immediately: Bool = false) {
        if newValue == nil, info != nil, !immediately {
            guard clearTask == nil else { return }
            clearTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: Self.transitionGrace)
                guard let self, !Task.isCancelled else { return }
                self.clearTask = nil
                self.apply(nil)
            }
            return
        }
        clearTask?.cancel()
        clearTask = nil
        apply(newValue)
    }

    private func apply(_ newValue: NowPlayingInfo?) {
        guard newValue != info else { return }
        let titleChanged = newValue?.title != info?.title
        info = newValue
        let data = newValue?.artworkData
        if data != artworkSource {
            if data == nil, newValue != nil, artwork != nil, titleChanged || artworkHoldTask != nil {
                // Yeni şarkı, kapağı henüz yok: eskisi kısa süre kalır, gelmezse temizlenir.
                artworkHoldTask?.cancel()
                artworkHoldTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: Self.artworkHold)
                    guard let self, !Task.isCancelled else { return }
                    self.artworkHoldTask = nil
                    self.setArtwork(nil)
                }
            } else {
                setArtwork(data)
            }
        }
        onInfoChanged?(newValue)
    }

    private func setArtwork(_ data: Data?) {
        artworkHoldTask?.cancel()
        artworkHoldTask = nil
        artworkSource = data
        let image = data.flatMap(NSImage.init(data:))
        artwork = image
        accentColor = image.flatMap(ArtworkAccent.color(of:))
        artworkVersion &+= 1
    }
}
