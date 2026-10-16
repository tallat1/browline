import Foundation

/// URL şeması: Raycast, Alfred, Kestirmeler "URL'yi Aç" ve betikler için.
/// `browline://push?id=build&title=Derleme&progress=40%25&symbol=hammer`
/// `browline://end?id=build` · `browline://flash?title=Bitti&duration=3`
/// Yanıt kanalı olmadığı için yalnız push, end ve flash. Alan sınırları sokettekiyle aynı.
public enum ActivityURL {
    public static let scheme = "browline"

    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case scheme
        case operation(String)
        case unknownParameter(String)
        case number(String)

        public var description: String { description(in: .current) }

        public func description(in language: APILanguage) -> String {
            switch self {
            case .scheme:
                language.text("şema \(ActivityURL.scheme):// olmalı", "the scheme must be \(ActivityURL.scheme)://")
            case let .operation(name):
                language.text("bilinmeyen işlem: \(name) (push, end, flash)", "unknown operation: \(name) (push, end, flash)")
            case let .unknownParameter(name):
                language.text("bilinmeyen parametre: \(name)", "unknown parameter: \(name)")
            case let .number(name):
                language.text("\(name) sayı olmalı", "\(name) must be a number")
            }
        }
    }

    private static let parameters: Set<String> = ["id", "title", "subtitle", "progress", "symbol", "tint",
                                                    "priority", "ttl", "duration"]

    public static func request(from url: URL) throws(ParseError) -> ActivityRequest {
        guard url.scheme?.lowercased() == scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw .scheme }
        // browline://push?… ya da browline:push?…
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
        func integer(_ key: String) throws(ParseError) -> Int? {
            guard let value = try number(key) else { return nil }
            guard let integer = ActivityRequest.integer(from: value) else { throw .number(key) }
            return integer
        }
        return ActivityRequest(op: operation, id: values["id"], title: values["title"], subtitle: values["subtitle"],
                               progress: try number("progress"), symbol: values["symbol"], tint: values["tint"],
                               priority: try integer("priority"), ttl: try number("ttl"),
                               duration: try number("duration"))
    }
}

extension ActivityRequest {
    /// `0.4` ya da `40%`; komut satırı ve URL şeması aynı kuralı kullanır. Sonsuz ve NaN reddedilir.
    public static func number(from raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let value = trimmed.hasSuffix("%") ? Double(trimmed.dropLast()).map { $0 / 100 } : Double(trimmed)
        return value.flatMap { $0.isFinite ? $0 : nil }
    }

    /// Öncelik gibi tam sayı alanlar: `Int(Double)` sonsuzda, NaN'da ve Int'e sığmayan değerde çöker
    /// (bir web sayfasındaki `browline://push?priority=1e999` bağlantısı uygulamayı düşürüyordu).
    public static func integer(from value: Double) -> Int? {
        guard value.isFinite else { return nil }
        return Int(exactly: value.rounded())
    }
}
