import Foundation

/// Şu an çalan medya. Kaynaktan bağımsız: adaptör de oynatıcı bildirimleri de bunu üretir.
public struct NowPlayingInfo: Equatable, Sendable {
    public var bundleIdentifier: String?
    public var title: String
    public var artist: String?
    public var album: String?
    public var duration: TimeInterval?
    /// `timestamp` anındaki konum.
    public var elapsedTime: TimeInterval?
    public var timestamp: Date?
    public var playbackRate: Double
    public var isPlaying: Bool
    public var artworkData: Data?

    public init(bundleIdentifier: String? = nil, title: String, artist: String? = nil, album: String? = nil,
                duration: TimeInterval? = nil, elapsedTime: TimeInterval? = nil, timestamp: Date? = nil,
                playbackRate: Double = 1, isPlaying: Bool, artworkData: Data? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.elapsedTime = elapsedTime
        self.timestamp = timestamp
        self.playbackRate = playbackRate
        self.isPlaying = isPlaying
        self.artworkData = artworkData
    }

    /// Verilen andaki tahmini konum: örnek alınan konum + geçen süre × hız, süreye kırpılmış.
    /// Böylece ilerleme çubuğu kaynağı yoklamadan güncellenir.
    public func elapsed(at date: Date) -> TimeInterval? {
        guard let elapsedTime else { return nil }
        var value = elapsedTime
        if isPlaying, let timestamp {
            value += max(0, date.timeIntervalSince(timestamp)) * playbackRate
        }
        if let duration, duration > 0 { value = min(value, duration) }
        return max(0, value)
    }

    /// Parça kimliği: aynı parçanın konum güncellemeleri kapak ya da renk yeniden hesaplatmasın.
    public var trackKey: String {
        [bundleIdentifier ?? "", title, artist ?? "", album ?? ""].joined(separator: "\u{1F}")
    }
}
