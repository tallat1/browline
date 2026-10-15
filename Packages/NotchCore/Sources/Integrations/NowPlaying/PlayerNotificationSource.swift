import AppKit

/// Adaptör çalışmadığında yedek: Music ve Spotify'ın dağıtık bildirimleri (okuma için izin
/// istemez) ve AppleScript komutları (Automation izni ister). Kapak ve konum yok.
/// ⚠️ Bildirim anahtarları belgelenmemiş; macOS 26/27'de doğrulanmadı.
@MainActor
final class PlayerNotificationSource {
    struct Player {
        let bundleIdentifier: String
        let notification: String
    }

    nonisolated static let players = [
        Player(bundleIdentifier: "com.apple.Music", notification: "com.apple.Music.playerInfo"),
        Player(bundleIdentifier: "com.spotify.client", notification: "com.spotify.client.PlaybackStateChanged"),
    ]

    var onUpdate: ((NowPlayingInfo?) -> Void)?
    private var tokens: [NSObjectProtocol] = []
    private var latest: [String: NowPlayingInfo] = [:]

    func start() {
        guard tokens.isEmpty else { return }
        let center = DistributedNotificationCenter.default()
        for player in Self.players {
            let token = center.addObserver(forName: Notification.Name(player.notification), object: nil,
                                           queue: .main) { [weak self] note in
                let info = Self.parse(note.userInfo, bundleIdentifier: player.bundleIdentifier)
                MainActor.assumeIsolated {
                    self?.handle(info, bundleIdentifier: player.bundleIdentifier)
                }
            }
            tokens.append(token)
        }
    }

    func stop() {
        let center = DistributedNotificationCenter.default()
        tokens.forEach(center.removeObserver)
        tokens.removeAll()
        latest.removeAll()
    }

    private func handle(_ info: NowPlayingInfo?, bundleIdentifier: String) {
        latest[bundleIdentifier] = info
        // Çalan varsa o, yoksa duraklatılmış son parça.
        let all = latest.values
        onUpdate?(all.first(where: \.isPlaying) ?? all.first)
    }

    nonisolated static func parse(_ userInfo: [AnyHashable: Any]?, bundleIdentifier: String) -> NowPlayingInfo? {
        guard let userInfo, let state = userInfo["Player State"] as? String, state != "Stopped",
              let title = userInfo["Name"] as? String, !title.isEmpty else { return nil }
        // Music "Total Time" (ms), Spotify "Duration" (ms) ve "Playback Position" (sn) gönderiyor.
        let durationMillis = (userInfo["Total Time"] ?? userInfo["Duration"]) as? NSNumber
        let position = userInfo["Playback Position"] as? NSNumber
        let playing = state == "Playing"
        return NowPlayingInfo(
            bundleIdentifier: bundleIdentifier,
            title: title,
            artist: userInfo["Artist"] as? String,
            album: userInfo["Album"] as? String,
            duration: durationMillis.map { $0.doubleValue / 1000 },
            elapsedTime: position?.doubleValue,
            timestamp: position == nil ? nil : .now,
            playbackRate: playing ? 1 : 0,
            isPlaying: playing)
    }

    /// Music ve Spotify konumu AppleScript ile değiştirir. Spotify MediaRemote konum komutunu doğru
    /// işlemiyor (2026-10-16: 2 sn geri istendi, sonraki şarkıya geçti); bu ikisinde yol bu.
    nonisolated static func supportsScriptedSeek(_ bundleIdentifier: String) -> Bool {
        players.contains { $0.bundleIdentifier == bundleIdentifier }
    }

    /// Ayrı `osascript` süreciyle: ana iş parçacığını bekletmez (ilk seferde Automation izni sorulur).
    nonisolated static func seek(to seconds: TimeInterval, bundleIdentifier: String) {
        guard supportsScriptedSeek(bundleIdentifier),
              !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty else { return }
        let position = String(format: "%.2f", max(0, seconds))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "tell application id \"\(bundleIdentifier)\" to set player position to \(position)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { finished in
            if finished.terminationStatus != 0 {
                Log.integrations.error("AppleScript konum komutu başarısız: \(finished.terminationStatus)")
            }
        }
        do { try process.run() } catch {
            Log.integrations.error("osascript başlatılamadı: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Oynatıcı açık değilse komut gönderilmez: `tell application` kapalı uygulamayı başlatır.
    func send(_ command: MediaRemoteAdapterBundle.Command, to bundleIdentifier: String) {
        guard Self.players.contains(where: { $0.bundleIdentifier == bundleIdentifier }),
              !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
        else { return }
        let verb = switch command {
        case .play: "play"
        case .pause: "pause"
        case .togglePlayPause: "playpause"
        case .nextTrack: "next track"
        case .previousTrack: "previous track"
        }
        var error: NSDictionary?
        NSAppleScript(source: "tell application id \"\(bundleIdentifier)\" to \(verb)")?.executeAndReturnError(&error)
        if let error {
            Log.integrations.error("AppleScript komutu başarısız: \(String(describing: error), privacy: .public)")
        }
    }
}
