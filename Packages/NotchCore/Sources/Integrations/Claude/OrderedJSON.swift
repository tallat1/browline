import Foundation

/// Anahtar sırasını ve sayıların yazılışını koruyan JSON. Kullanıcının elle de düzenlediği ayar dosyasına (Claude Code
/// `settings.json`) yalnız kendi bölümümüz değişecek biçimde yazmak için: `JSONSerialization` sırayı karıştırır.
/// Çıktı `JSON.stringify(value, null, 2)` biçiminde; Claude Code dosyayı böyle yazıyor, değişmeyen dosya aynı çıkar.
enum OrderedJSON: Equatable {
    case object([(String, OrderedJSON)])
    case array([OrderedJSON])
    case string(String)
    /// Kaynaktaki yazılışıyla (`60`, `1.5e3`).
    case number(String)
    case bool(Bool)
    case null

    static func == (lhs: OrderedJSON, rhs: OrderedJSON) -> Bool {
        switch (lhs, rhs) {
        case let (.object(a), .object(b)): a.count == b.count && zip(a, b).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        case let (.array(a), .array(b)): a == b
        case let (.string(a), .string(b)): a == b
        case let (.number(a), .number(b)): a == b
        case let (.bool(a), .bool(b)): a == b
        case (.null, .null): true
        default: false
        }
    }

    // MARK: - Erişim

    subscript(key: String) -> OrderedJSON? {
        guard case let .object(pairs) = self else { return nil }
        return pairs.first { $0.0 == key }?.1
    }

    var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    var arrayValue: [OrderedJSON]? {
        if case let .array(value) = self { return value }
        return nil
    }

    /// Var olan anahtar yerinde değişir, yoksa sona eklenir; nil anahtarı siler.
    func setting(_ key: String, to value: OrderedJSON?) -> OrderedJSON {
        guard case var .object(pairs) = self else { return self }
        if let index = pairs.firstIndex(where: { $0.0 == key }) {
            if let value { pairs[index].1 = value } else { pairs.remove(at: index) }
        } else if let value {
            pairs.append((key, value))
        }
        return .object(pairs)
    }

    // MARK: - Okuma

    struct ParseError: Error {}

    static func parse(_ data: Data) throws -> OrderedJSON {
        var parser = Parser(bytes: Array(data))
        parser.skipWhitespace()
        let value = try parser.value()
        parser.skipWhitespace()
        guard parser.index == parser.bytes.count else { throw ParseError() }
        return value
    }

    private struct Parser {
        let bytes: [UInt8]
        var index = 0

        mutating func skipWhitespace() {
            while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
        }

        mutating func value() throws -> OrderedJSON {
            guard index < bytes.count else { throw ParseError() }
            switch bytes[index] {
            case UInt8(ascii: "{"): return try object()
            case UInt8(ascii: "["): return try array()
            case UInt8(ascii: "\""): return .string(try string())
            case UInt8(ascii: "t"): try literal("true"); return .bool(true)
            case UInt8(ascii: "f"): try literal("false"); return .bool(false)
            case UInt8(ascii: "n"): try literal("null"); return .null
            default: return try number()
            }
        }

        mutating func literal(_ word: String) throws {
            let expected = Array(word.utf8)
            guard index + expected.count <= bytes.count, Array(bytes[index..<index + expected.count]) == expected else {
                throw ParseError()
            }
            index += expected.count
        }

        mutating func object() throws -> OrderedJSON {
            index += 1
            var pairs: [(String, OrderedJSON)] = []
            skipWhitespace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "}") { index += 1; return .object(pairs) }
            while true {
                skipWhitespace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else { throw ParseError() }
                let key = try string()
                skipWhitespace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { throw ParseError() }
                index += 1
                skipWhitespace()
                pairs.append((key, try value()))
                skipWhitespace()
                guard index < bytes.count else { throw ParseError() }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                if bytes[index] == UInt8(ascii: "}") { index += 1; return .object(pairs) }
                throw ParseError()
            }
        }

        mutating func array() throws -> OrderedJSON {
            index += 1
            var items: [OrderedJSON] = []
            skipWhitespace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "]") { index += 1; return .array(items) }
            while true {
                skipWhitespace()
                items.append(try value())
                skipWhitespace()
                guard index < bytes.count else { throw ParseError() }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                if bytes[index] == UInt8(ascii: "]") { index += 1; return .array(items) }
                throw ParseError()
            }
        }

        mutating func number() throws -> OrderedJSON {
            let start = index
            while index < bytes.count, "+-0123456789.eE".utf8.contains(bytes[index]) { index += 1 }
            let text = String(decoding: bytes[start..<index], as: UTF8.self)
            guard !text.isEmpty, Double(text) != nil else { throw ParseError() }
            return .number(text)
        }

        /// Kaçışlar JSONSerialization'a bırakılır: tek dizgiyi ayrıştırmak için doğru ve yeterli.
        mutating func string() throws -> String {
            let start = index
            index += 1
            while index < bytes.count {
                if bytes[index] == UInt8(ascii: "\\") { index += 2; continue }
                if bytes[index] == UInt8(ascii: "\"") { break }
                index += 1
            }
            guard index < bytes.count else { throw ParseError() }
            index += 1
            let literal = Data(bytes[start..<index])
            guard let value = try? JSONSerialization.jsonObject(with: literal, options: .fragmentsAllowed) as? String else {
                throw ParseError()
            }
            return value
        }
    }

    // MARK: - Yazma

    /// `JSON.stringify(value, null, 2)` ile aynı biçim.
    func serialized(indent: Int = 0) -> String {
        let pad = String(repeating: "  ", count: indent)
        let inner = String(repeating: "  ", count: indent + 1)
        switch self {
        case let .object(pairs):
            guard !pairs.isEmpty else { return "{}" }
            let body = pairs.map { "\(inner)\(Self.quote($0.0)): \($0.1.serialized(indent: indent + 1))" }
            return "{\n" + body.joined(separator: ",\n") + "\n\(pad)}"
        case let .array(items):
            guard !items.isEmpty else { return "[]" }
            return "[\n" + items.map { inner + $0.serialized(indent: indent + 1) }.joined(separator: ",\n") + "\n\(pad)]"
        case let .string(value): return Self.quote(value)
        case let .number(text): return text
        case let .bool(value): return value ? "true" : "false"
        case .null: return "null"
        }
    }

    /// JSON.stringify kaçışları: tırnak, ters bölü, denetim karakterleri; geri kalan (Türkçe dahil) olduğu gibi.
    static func quote(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            case "\u{08}": result += "\\b"
            case "\u{0C}": result += "\\f"
            case _ where scalar.value < 0x20: result += String(format: "\\u%04x", scalar.value)
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }
}
