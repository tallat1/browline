import Foundation

/// Etkinlik metinlerinden toplantı bağlantısını bulur (Zoom, Meet, Teams, Webex, FaceTime, Whereby).
public enum MeetingLink {
    static let hosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com",
                        "webex.com", "facetime.apple.com", "whereby.com"]

    /// Önce etkinliğin kendi URL'si, sonra konum, sonra notlar aranır.
    public static func find(url: URL?, location: String?, notes: String?) -> URL? {
        if let url, isMeeting(url) { return url }
        for text in [location, notes].compactMap({ $0 }) {
            if let found = firstMeetingURL(in: text) { return found }
        }
        return nil
    }

    static func isMeeting(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(), url.scheme?.hasPrefix("http") == true else { return false }
        return hosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    static func firstMeetingURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, range: range) {
            if let url = match.url, isMeeting(url) { return url }
        }
        return nil
    }
}
