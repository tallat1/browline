import Foundation

/// URL şeması: Raycast, Alfred, Kestirmeler "URL'yi Aç" ve betikler için.
/// `notchmvp://push?id=build&title=Derleme&progress=40%25&symbol=hammer`
/// `notchmvp://end?id=build` · `notchmvp://flash?title=Bitti&duration=3`
/// Yanıt kanalı olmadığı için yalnız push, end ve flash. Alan sınırları sokettekiyle aynı.
public enum ActivityURL {
    public static let scheme = "notchmvp"

    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case scheme
        case operation(String)
        case unknownParameter(String)
        case number(String)

        public var description: String {
            switch self {
            case .scheme: "şema \(ActivityURL.scheme):// olmalı"
            case let .operation(name): "bilinmeyen işlem: \(name) (push, end, flash)"
            case let .unknownParameter(name): "bilinmeyen parametre: \(name)"
            case let .number(name): "\(name) sayı olmalı"
            }
        }
    }

    private static let parameters: Set<String> = ["id", "title", "subtitle", "progress", "symbol", "tint",
                                                    "priority", "ttl", "duration"]

    public static func request(from url: URL) throws(ParseError) -> ActivityRequest {
        guard url.scheme?.lowercased() == scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw .scheme }
        // notchmvp://push?… ya da notchmvp:push?…
        let name = (components.host ?? components.path).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let operation: ActivityRequest.Operation
        switch name.lowercased() {
        case "push": operation = .push
        case "end": operation = .end
        case "flash": operation = .flash
        default: throw .operation(name)
        }
        var values: [String: String] = [:]
        for item in components.queryItems ?? [] {
            guard parameters.contains(item.name) else { throw .unknownParameter(item.name) }
            values[item.name] = item.value ?? ""
        }
        func number(_ key: String) throws(ParseError) -> Double? {
            guard let raw = values[key] else { return nil }
            guard let value = ActivityRequest.number(from: raw) else { throw .number(key) }
            return value
        }
        return ActivityRequest(op: operation, id: values["id"], title: values["title"], subtitle: values["subtitle"],
                               progress: try number("progress"), symbol: values["symbol"], tint: values["tint"],
                               priority: try number("priority").map { Int($0) }, ttl: try number("ttl"),
                               duration: try number("duration"))
    }
}

extension ActivityRequest {
    /// `0.4` ya da `40%`; komut satırı ve URL şeması aynı kuralı kullanır.
    public static func number(from raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix("%") { return Double(trimmed.dropLast()).map { $0 / 100 } }
        return Double(trimmed)
    }
}
