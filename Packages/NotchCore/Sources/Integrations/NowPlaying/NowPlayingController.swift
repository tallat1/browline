import AppKit
import Observation

/// Katmanlı Now Playing: önce adaptörü `test` ile yoklar; geçerse `stream`, geçmezse oynatıcı
/// bildirimleri. Arayüz hangi kaynağın kullanıldığını gösterir (raporun önerisi).
///
/// Adaptör yalnız sistemin seçtiği oynatıcıyı verir; çoklu oturum yardımcısı (varsa) diğerlerini de
/// listeler. `info` odaktaki oturumdur: elle seçilen, yoksa çalan (sistem duraklatılmış bir videoyu
/// seçmiş olsa bile). Odaktaki oturum sistemin seçtiği değilse komutlar doğrudan ona gider.
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
    /// Tüm oynatıcılar, ilk görülme sırasıyla (seçici titremesin). Yardımcı yoksa en çok bir tane.
    public private(set) var sessions: [MediaSession] = []
    public private(set) var focusedSessionID: String?
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
    @ObservationIgnored private var sessionsBundle: MediaSessionsBundle?
    @ObservationIgnored private var sessionsStream: MediaSessionsStream?
    @ObservationIgnored private var sessionsRestartAttempt = 0
    /// Yardımcının bildirdiği oturumlar (sistemin seçtiği dahil).
    @ObservationIgnored private var helperSessions: [MediaSession] = []
    /// Sistemin seçtiği oynatıcı: adaptör akışı, geçiş payından sonra.
    @ObservationIgnored private var systemInfo: NowPlayingInfo?
    @ObservationIgnored private var selectedSessionID: String?
    @ObservationIgnored private var playStartedAt: [String: Date] = [:]
    @ObservationIgnored private var sessionOrder: [String: Int] = [:]
    @ObservationIgnored private var nextSessionOrder = 0

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
                self.startSessions()
            } else {
                self.useFallback(reason: .adapterTestFailed)
            }
        }
    }

    public func stop() {
        generation += 1
        stream?.stop()
        stream = nil
        stopSessions()
        selectedSessionID = nil
        fallback.stop()
        source = .off
        set(info: nil, immediately: true)
    }

    // MARK: - Oturumlar

    /// Medya sekmesindeki seçici: o oturum gösterilir, denetimler ona gider.
    public func selectSession(_ id: String) {
        guard sessions.contains(where: { $0.id == id }) else { return }
        selectedSessionID = id
        Log.integrations.notice("Medya: oturum seçildi (\(id, privacy: .public))")
        recompute()
    }

    /// Sekme kapanınca: seçilen oturum çalmıyorsa bırakılır, kapalı notch çalanı göstersin.
    public func releaseSelection() {
        guard let selected = selectedSessionID,
              sessions.first(where: { $0.id == selected })?.info.isPlaying != true else { return }
        selectedSessionID = nil
        recompute()
    }

    private var focusedSession: MediaSession? {
        sessions.first { $0.id == focusedSessionID }
    }

    /// Oynatıcı bildiriyorsa (Chrome'daki tek video bildirmez).
    public var canSkipTracks: Bool {
        focusedSession.map { $0.supports(.nextTrack) || $0.supports(.previousTrack) } ?? true
    }

    /// Odaktaki oturum sistemin seçtiği değilse süreç kimliği: komut doğrudan ona gider.
    private var directTarget: Int32? {
        guard sessionsBundle != nil,
              let focused = sessions.first(where: { $0.id == focusedSessionID }) else { return nil }
        if let systemInfo, focused.matches(systemInfo) { return nil }
        return focused.info.processIdentifier
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
        let direct = directTarget
        if let bundle = current.bundleIdentifier, PlayerNotificationSource.supportsScriptedSeek(bundle) {
            PlayerNotificationSource.seek(to: target, bundleIdentifier: bundle)
            Log.integrations.notice("Medya: konum \(Int(target)) sn (AppleScript, \(bundle, privacy: .public))")
        } else if let direct, let sessionsBundle {
            sessionsBundle.seek(to: target, pid: direct)
            Log.integrations.notice("Medya: konum \(Int(target)) sn (doğrudan oynatıcıya, süreç \(direct))")
        } else {
            adapter.seek(to: target)
            Log.integrations.notice("Medya: konum \(Int(target)) sn (MediaRemote)")
        }
        // İyimser güncelleme: çubuk akıştan gelecek düzeltmeyi beklemeden yeni konuma atlar.
        current.elapsedTime = target
        current.timestamp = .now
        if direct != nil, let index = helperSessions.firstIndex(where: { $0.id == focusedSessionID }) {
            helperSessions[index].info = current
            recompute()
        } else {
            set(info: current)
        }
    }

    /// İleri ya da geri (saniye). Oynatıcının kendi 15 sn komutu yerine seek: Spotify onu bildirmiyor.
    public func skip(by seconds: TimeInterval) {
        guard let elapsed = info?.elapsed(at: .now) else { return }
        seek(to: elapsed + seconds)
    }

    /// Karıştırma ve tekrar yalnız oynatıcı durumunu bildiriyorsa (Music evet, Spotify hayır) ve
    /// odaktaki oturum sistemin seçtiğiyse (adaptör komutu ona gider).
    public var supportsShuffleAndRepeat: Bool {
        source == .mediaRemote && directTarget == nil && info?.shuffleMode != nil && info?.repeatMode != nil
    }

    /// Kapalı → parça karıştırma → kapalı.
    public func cycleShuffle() {
        guard supportsShuffleAndRepeat, let adapter, let mode = info?.shuffleMode else { return }
        adapter.setShuffle(Self.nextShuffleMode(after: mode))
    }

    nonisolated static func nextShuffleMode(after mode: Int) -> Int { mode == 1 ? 3 : 1 }

    nonisolated static func nextRepeatMode(after mode: Int) -> Int { mode == 1 ? 3 : (mode == 3 ? 2 : 1) }

    /// Kapalı → listeyi tekrarla → parçayı tekrarla → kapalı.
    public func cycleRepeat() {
        guard supportsShuffleAndRepeat, let adapter, let mode = info?.repeatMode else { return }
        adapter.setRepeat(Self.nextRepeatMode(after: mode))
    }

    private func send(_ command: MediaRemoteAdapterBundle.Command) {
        switch source {
        case .mediaRemote:
            if directTarget != nil, let bundle = info?.bundleIdentifier,
               PlayerNotificationSource.supportsScriptedSeek(bundle) {
                PlayerNotificationSource.sendScripted(command, bundleIdentifier: bundle)
                Log.integrations.notice("Medya: komut \(command.rawValue) AppleScript ile (\(bundle, privacy: .public))")
            } else if let direct = directTarget, let sessionsBundle {
                sessionsBundle.send(command, to: direct)
                Log.integrations.notice("Medya: komut \(command.rawValue) doğrudan oynatıcıya (süreç \(direct))")
            } else {
                adapter?.send(command)
            }
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

    /// Çoklu oturum yardımcısı; yoksa ya da çökerse tek oturumla (adaptör) devam edilir.
    private func startSessions() {
        guard sessionsStream == nil, let bundle = sessionsBundle ?? MediaSessionsBundle.locate() else { return }
        sessionsBundle = bundle
        let stream = MediaSessionsStream(bundle: bundle)
        let current = generation
        do {
            try stream.start(
                onUpdate: { [weak self] sessions in
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            guard let self, self.generation == current else { return }
                            self.helperSessions = sessions
                            self.recompute()
                        }
                    }
                },
                onExit: { [weak self] status, stoppedByUs in
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            guard let self, !stoppedByUs, self.generation == current else { return }
                            self.sessionsExited(status: status)
                        }
                    }
                })
            sessionsStream = stream
            Log.integrations.info("Now Playing: oturum yardımcısı başladı")
        } catch {
            Log.integrations.error("Oturum yardımcısı başlatılamadı: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func stopSessions() {
        sessionsStream?.stop()
        sessionsStream = nil
        helperSessions = []
    }

    private func sessionsExited(status: Int32) {
        sessionsStream = nil
        helperSessions = []
        recompute()
        // Sıfır dışı çıkış (MediaRemote işlevi yok vb.) kalıcı sayılır: tek oturumla devam.
        guard status == 0, sessionsRestartAttempt < Self.restartDelays.count else {
            sessionsBundle = nil
            Log.integrations.notice("Oturum yardımcısı durdu (\(status)); tek oturumla devam")
            return
        }
        let delay = Self.restartDelays[sessionsRestartAttempt]
        sessionsRestartAttempt += 1
        let current = generation
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, self.generation == current else { return }
            self.startSessions()
        }
    }

    private func useFallback(reason: FallbackReason) {
        stream?.stop()
        stream = nil
        stopSessions()
        source = .playerNotifications(reason)
        Log.integrations.notice("Now Playing yedeğe düştü: \(reason.description, privacy: .public)")
        fallback.onUpdate = { [weak self] info in self?.set(info: info) }
        fallback.start()
    }

    private func set(info newValue: NowPlayingInfo?, immediately: Bool = false) {
        if newValue == nil, systemInfo != nil, !immediately {
            guard clearTask == nil else { return }
            clearTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: Self.transitionGrace)
                guard let self, !Task.isCancelled else { return }
                self.clearTask = nil
                self.systemInfo = nil
                self.recompute()
            }
            return
        }
        clearTask?.cancel()
        clearTask = nil
        systemInfo = newValue
        recompute()
    }

    /// Sistemin seçtiği oynatıcı ile yardımcının listesini birleştirir, odağı seçer ve gösterir.
    private func recompute() {
        var list = helperSessions
        var systemID: String?
        if let systemInfo {
            if let index = list.firstIndex(where: { $0.matches(systemInfo) }) {
                // Sistemin seçtiğinde adaptör akışı esas: kapak tutma ve geçiş payı onda.
                list[index].info = systemInfo
                systemID = list[index].id
            } else {
                let session = MediaSession(systemInfo: systemInfo)
                list.append(session)
                systemID = session.id
            }
        }
        for session in list where sessionOrder[session.id] == nil {
            sessionOrder[session.id] = nextSessionOrder
            nextSessionOrder += 1
        }
        list.sort { sessionOrder[$0.id, default: 0] < sessionOrder[$1.id, default: 0] }

        let wasPlaying = Set(sessions.filter(\.info.isPlaying).map(\.id))
        for session in list where session.info.isPlaying && !wasPlaying.contains(session.id) {
            playStartedAt[session.id] = .now
            // Başka bir oynatıcı çalmaya başladıysa elle seçim bırakılır: yeni çalan öne gelir.
            if let selected = selectedSessionID, selected != session.id { selectedSessionID = nil }
        }
        let ids = Set(list.map(\.id))
        playStartedAt = playStartedAt.filter { ids.contains($0.key) }
        sessionOrder = sessionOrder.filter { ids.contains($0.key) }
        if let selected = selectedSessionID, !ids.contains(selected) { selectedSessionID = nil }

        if list.map(\.id) != sessions.map(\.id) {
            let summary = list.map { "\($0.info.bundleIdentifier ?? "?") \($0.info.isPlaying ? "▶" : "⏸")" }
            Log.integrations.notice("Medya oturumları: \(summary.joined(separator: ", "), privacy: .public)")
        }
        if list != sessions { sessions = list }
        let focus = MediaSession.focus(in: list, selected: selectedSessionID, system: systemID,
                                       playStartedAt: playStartedAt)
        if focusedSessionID != focus?.id { focusedSessionID = focus?.id }
        present(focus?.info)
    }

    private func present(_ newValue: NowPlayingInfo?) {
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
