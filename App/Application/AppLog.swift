import os

/// Uygulama katmanının günlüğü. Elle denemeler bu satırlardan doğrulanır; kişisel metin (başlık,
/// dosya adı) yazılmaz, yalnız kimlik, sayı ve durum.
enum AppLog {
    static let coordinator = Logger(subsystem: "com.talatozcoban.browline", category: "app")
}
