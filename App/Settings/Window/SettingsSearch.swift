import Foundation

/// Ayar araması: ad ve anahtar sözcük dizini (Atoll gibi). Sonuca basınca sayfa açılır, satıra
/// kaydırılır ve kısa süre vurgulanır. Kimlikler sayfalardaki `settingsAnchor` ile aynı olmalı.
struct SettingsSearchEntry: Identifiable, Hashable {
    let id: String
    let page: SettingsPage
    let title: String
    /// İki dilde eş anlamlılar: arayan kişi uygulamanın dilinde düşünmeyebilir.
    let keywords: [String]
}

enum SettingsSearch {
    static var entries: [SettingsSearchEntry] {
        var list: [SettingsSearchEntry] = [
            .init(id: "launchAtLogin", page: .general, title: String(localized: "Girişte başlat"), keywords: ["login", "startup", "açılış", "başlangıç"]),
            .init(id: "onboarding", page: .general, title: String(localized: "Karşılama"), keywords: ["hoş geldiniz", "welcome", "onboarding", "profil", "profile", "başlangıç"]),
            .init(id: "updates", page: .general, title: String(localized: "Güncellemeler"), keywords: ["update", "güncelleme", "sparkle", "sürüm", "version", "yeni sürüm"]),
            .init(id: "displays", page: .general, title: String(localized: "Ekranlar"), keywords: ["display", "monitör", "monitor", "dış ekran", "hap", "pill", "yüzen", "floating"]),
            .init(id: "openDelay", page: .notch, title: String(localized: "Üzerine gelince açılma"), keywords: ["hover", "gecikme", "delay", "aç"]),
            .init(id: "haptics", page: .notch, title: String(localized: "Dokunsal geri bildirim"), keywords: ["haptic", "trackpad", "titreşim", "force touch"]),
            .init(id: "weather", page: .notch, title: String(localized: "Hava durumu"), keywords: ["weather", "şehir", "city", "sıcaklık", "temperature"]),
            .init(id: "keepAwake", page: .notch, title: String(localized: "Uyanık tutma düğmesi"), keywords: ["caffeinate", "uyku", "sleep", "awake", "fincan"]),
            .init(id: "battery", page: .notch, title: String(localized: "Pil ve şarj"), keywords: ["battery", "şarj", "charge", "pil"]),
            .init(id: "equalizer", page: .notch, title: String(localized: "Çalarken hareketli çubuklar"), keywords: ["equalizer", "çubuk", "bars", "animasyon"]),
            .init(id: "reactive", page: .notch, title: String(localized: "Çubuklar müziğe tepki versin"), keywords: ["spectrum", "spektrum", "ses", "audio", "tepki"]),
            .init(id: "lowPower", page: .notch, title: String(localized: "Düşük Güç Modu'nda hareketi durdur"), keywords: ["low power", "enerji", "pil", "battery"]),
            .init(id: "hiding", page: .notch, title: String(localized: "Gizleme"), keywords: ["tam ekran", "full screen", "mission control", "oyun", "game", "ekran kaydı", "screen recording", "gizle", "hide"]),
            .init(id: "media", page: .now, title: String(localized: "Çalan müzik ve video"), keywords: ["now playing", "müzik", "music", "spotify", "medya", "video"]),
            .init(id: "meeting", page: .now, title: String(localized: "Mikrofonu sistem genelinde sessize alma"), keywords: ["toplantı", "meeting", "mikrofon", "microphone", "mute", "sessiz", "zoom", "teams"]),
            .init(id: "micShortcut", page: .now, title: String(localized: "Sessize alma kısayolu"), keywords: ["kısayol", "shortcut", "klavye", "⌃⌥M"]),
            .init(id: "activities", page: .now, title: String(localized: "Betik ve AI ajanı etkinlikleri"), keywords: ["api", "betik", "script", "ajan", "agent", "etkinlik", "activity", "notch push"]),
            .init(id: "urlScheme", page: .now, title: String(localized: "browline:// bağlantıları"), keywords: ["url", "şema", "scheme", "raycast", "alfred", "kestirme", "shortcuts", "bağlantı", "link"]),
            .init(id: "questions", page: .now, title: String(localized: "Claude Code izin istemlerini notch'ta yanıtla"), keywords: ["claude", "izin", "permission", "onay", "approve"]),
            .init(id: "choiceQuestions", page: .now, title: String(localized: "Claude'un seçenekli sorularını notch'ta yanıtla"), keywords: ["claude", "soru", "question", "seçenek", "choice", "askuserquestion"]),
            .init(id: "decisionCards", page: .now, title: String(localized: "Claude'un karar kutularını notch'ta göster"), keywords: ["claude", "karar", "decision", "masaüstü", "desktop", "bekliyor", "waiting"]),
            .init(id: "shelf", page: .shelf, title: String(localized: "Dosya rafı"), keywords: ["raf", "shelf", "dosya", "file", "airdrop", "sürükle", "drag", "ekran görüntüsü", "screenshot"]),
            .init(id: "clipboard", page: .shelf, title: String(localized: "Pano geçmişi"), keywords: ["pano", "clipboard", "kopyala", "copy", "yapıştır", "paste"]),
            .init(id: "calendar", page: .calendar, title: String(localized: "Takvim ve toplantılar"), keywords: ["takvim", "calendar", "toplantı", "meeting", "etkinlik", "event"]),
            .init(id: "reminders", page: .calendar, title: String(localized: "Bugünün anımsatıcıları"), keywords: ["anımsatıcı", "reminders", "görev", "todo"]),
            .init(id: "notes", page: .tools, title: String(localized: "Hızlı not"), keywords: ["not", "notes", "yazı"]),
            .init(id: "timer", page: .tools, title: String(localized: "Zamanlayıcı ve Pomodoro"), keywords: ["timer", "pomodoro", "süre", "sayaç"]),
            .init(id: "terminal", page: .tools, title: String(localized: "Terminal"), keywords: ["terminal", "kabuk", "shell", "komut"]),
            .init(id: "mirror", page: .tools, title: String(localized: "Ayna"), keywords: ["ayna", "mirror", "kamera", "camera"]),
            .init(id: "system", page: .status, title: String(localized: "İşlemci, bellek ve ağ"), keywords: ["sistem", "system", "cpu", "işlemci", "bellek", "memory", "ağ", "network"]),
            .init(id: "bluetooth", page: .status, title: String(localized: "Bluetooth aygıtları"), keywords: ["bluetooth", "airpods", "kulaklık", "headphones", "pil"]),
            .init(id: "claude", page: .status, title: String(localized: "Claude limitleri"), keywords: ["claude", "limit", "kullanım", "usage"]),
            .init(id: "ci", page: .status, title: String(localized: "GitHub Actions durumu"), keywords: ["ci", "github", "actions", "derleme", "build", "gh", "depo", "repository"]),
            .init(id: "trackPeek", page: .indicators, title: String(localized: "Şarkı değişince"), keywords: ["şarkı", "track", "song", "bildirim"]),
            .init(id: "audioOutput", page: .indicators, title: String(localized: "Ses çıkışı değişince"), keywords: ["ses çıkışı", "output", "airpods", "hoparlör", "speaker"]),
            .init(id: "downloads", page: .indicators, title: String(localized: "İndirme bitince"), keywords: ["indirme", "download", "indirilenler"]),
            .init(id: "privacy", page: .indicators, title: String(localized: "Kamera ve mikrofon kullanımda"), keywords: ["gizlilik", "privacy", "kamera", "camera", "mikrofon", "microphone"]),
            .init(id: "screenRecording", page: .indicators, title: String(localized: "Ekran kaydediliyor ya da paylaşılıyor"), keywords: ["ekran kaydı", "screen recording", "paylaşım", "sharing"]),
            .init(id: "hud", page: .indicators, title: String(localized: "Ses ve parlaklık göstergesi"), keywords: ["hud", "osd", "ses", "volume", "parlaklık", "brightness"]),
            .init(id: "lockWidgets", page: .lockScreen, title: String(localized: "Müzik ve pil şeridi"), keywords: ["kilit", "lock", "kilit ekranı", "lock screen"]),
            .init(id: "lockScreen", page: .lockScreen, title: String(localized: "Kilit ekranında ayrı panel"), keywords: ["kilit", "lock", "deneysel", "skylight"]),
            .init(id: "api", page: .advanced, title: String(localized: "Etkinlik API'si ve notch komutu"), keywords: ["api", "soket", "socket", "cli", "komut", "command"]),
            .init(id: "source", page: .advanced, title: String(localized: "Medya kaynağı"), keywords: ["mediaremote", "kaynak", "source", "adapter"]),
            .init(id: "private", page: .advanced, title: String(localized: "Belgelenmemiş macOS işlevleri"), keywords: ["private", "belgelenmemiş", "skylight"]),
            .init(id: "about", page: .about, title: String(localized: "Sürüm ve lisanslar"), keywords: ["sürüm", "version", "lisans", "license", "hakkında", "about"]),
        ]
        list += PermissionKind.allCases.map {
            .init(id: "permission.\($0.rawValue)", page: .permissions, title: $0.systemName,
                  keywords: ["izin", "permission", "gizlilik", "privacy", $0.fallbackName])
        }
        return list
    }

    /// Ad, anahtar sözcük ve sayfa adında; büyük/küçük harf ve aksan duyarsız. Ad eşleşmesi önde.
    static func results(for query: String) -> [SettingsSearchEntry] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        func matches(_ value: String) -> Bool {
            value.range(of: text, options: [.caseInsensitive, .diacriticInsensitive], locale: .current) != nil
        }
        let all = entries
        let byTitle = all.filter { matches($0.title) }
        let byOther = all.filter { entry in
            !byTitle.contains(entry) && (entry.keywords.contains(where: matches) || matches(entry.page.title))
        }
        return Array((byTitle + byOther).prefix(12))
    }
}
