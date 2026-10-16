import Foundation

/// Komut satırı aracının ve etkinlik API'sinin kullanıcıya dönen metinleri: dil sırasının ilki Türkçeyse
/// Türkçe, değilse İngilizce. Araçta String Catalog yok; API yanıtları uygulama sürecinde üretilip araca ve
/// Kestirmeler'e gider. İkisi de aynı kullanıcının dil sırasını izler.
public enum APILanguage: Sendable, Equatable {
    case turkish
    case english

    public static var current: APILanguage { of(Locale.preferredLanguages) }

    /// Yalnız ilk dil belirler: ["en-TR", "tr-TR"] → İngilizce (uygulamanın kendisi de böyle açılır).
    public static func of(_ preferred: [String]) -> APILanguage {
        (preferred.first ?? "en").lowercased().hasPrefix("tr") ? .turkish : .english
    }

    public func text(_ turkish: String, _ english: String) -> String {
        self == .turkish ? turkish : english
    }
}
