import Foundation

/// mediaremote-adapter `stream --micros` çıktısını satır satır çözer.
///
/// Her satır `{"type":"data","diff":Bool,"payload":{…}}`. `diff == false` ise payload tüm durumdur;
/// `diff == true` ise yalnız değişen anahtarlar gelir ve `null` anahtarın kaybolduğu anlamına gelir.
/// Boş payload = hiçbir oynatıcı bilgi vermiyor. Başlık, bundle kimliği ya da `playing` eksikse
/// medya geçersiz sayılır (adaptör belgesi).
public struct AdapterStreamParser {
    public enum Update: Equatable, Sendable {
        case nothingPlaying
        case playing(NowPlayingInfo)
    }

    private var state: [String: Any] = [:]
    private var lastEmitted: Update?

    public init() {}

    /// Çözülemeyen ya da öncekiyle aynı sonucu veren satır için nil döner.
    public mutating func consume(line: String) -> Update? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["type"] as? String == "data",
              let payload = object["payload"] as? [String: Any] else { return nil }

        if object["diff"] as? Bool == true {
            for (key, value) in payload {
                if value is NSNull { state.removeValue(forKey: key) } else { state[key] = value }
            }
        } else {
            state = payload
        }

        let update = Self.makeUpdate(from: state)
        guard update != lastEmitted else { return nil }
        lastEmitted = update
        return update
    }

    static func makeUpdate(from state: [String: Any]) -> Update {
        guard let title = state["title"] as? String, !title.isEmpty,
              let bundleIdentifier = state["bundleIdentifier"] as? String,
              let playing = state["playing"] as? Bool else { return .nothingPlaying }
        let artwork = (state["artworkData"] as? String).flatMap { Data(base64Encoded: $0) }
        return .playing(NowPlayingInfo(
            bundleIdentifier: bundleIdentifier,
            title: title,
            artist: nonEmpty(state["artist"]),
            album: nonEmpty(state["album"]),
            duration: seconds(fromMicros: state["durationMicros"]),
            elapsedTime: seconds(fromMicros: state["elapsedTimeMicros"]),
            timestamp: seconds(fromMicros: state["timestampEpochMicros"]).map { Date(timeIntervalSince1970: $0) },
            playbackRate: (state["playbackRate"] as? NSNumber)?.doubleValue ?? (playing ? 1 : 0),
            isPlaying: playing,
            artworkData: artwork
        ))
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let string = value as? String, !string.isEmpty else { return nil }
        return string
    }

    private static func seconds(fromMicros value: Any?) -> TimeInterval? {
        (value as? NSNumber).map { $0.doubleValue / 1_000_000 }
    }
}
