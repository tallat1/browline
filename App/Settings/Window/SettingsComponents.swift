import Integrations
import SwiftUI

/// Ayarlar penceresinin sayfaları. Kenar çubuğunda üç grup: başlıksız üst (Genel, Notch, İzinler),
/// notch'un beş bölümü, Diğer; Hakkında en altta başlıksız. Notch'ta gördüğü yeri kullanıcı ayarlarda
/// aynı adla bulur (rakiplerde gruplar özellik türüne göre, bölüme göre değil).
enum SettingsPage: String, CaseIterable, Identifiable, Sendable {
    case general, notch, permissions
    case now, shelf, calendar, tools, status
    case indicators, lockScreen, advanced
    case about

    var id: String { rawValue }

    enum Group: CaseIterable {
        case top, sections, other, bottom

        var title: LocalizedStringKey? {
            switch self {
            case .sections: "Notch bölümleri"
            case .other: "Diğer"
            case .top, .bottom: nil
            }
        }
    }

    var group: Group {
        switch self {
        case .general, .notch, .permissions: .top
        case .now, .shelf, .calendar, .tools, .status: .sections
        case .indicators, .lockScreen, .advanced: .other
        case .about: .bottom
        }
    }

    var title: String {
        switch self {
        case .general: String(localized: "Genel")
        case .notch: String(localized: "Notch")
        case .permissions: String(localized: "İzinler")
        case .now: String(localized: "Şimdi")
        case .shelf: String(localized: "Raf")
        case .calendar: String(localized: "Takvim")
        case .tools: String(localized: "Araçlar")
        case .status: String(localized: "Durum")
        case .indicators: String(localized: "Göstergeler")
        case .lockScreen: String(localized: "Kilit ekranı")
        case .advanced: String(localized: "Gelişmiş")
        case .about: String(localized: "Hakkında")
        }
    }

    /// Sayfa başlığının altındaki tek cümle.
    var subtitle: String {
        switch self {
        case .general: String(localized: "Başlangıç ve hangi ekranda notch görüneceği.")
        case .notch: String(localized: "Açılma, hareket, sağ üstteki durum alanı ve gizleme.")
        case .permissions: String(localized: "Açık özelliklerin istediği izinler. Uygulama başka izin istemez.")
        case .now: String(localized: "Medya, toplantı ve o an önemli olanlar.")
        case .shelf: String(localized: "Dosyaları notch'a bırakın, sonra istediğiniz yere sürükleyin. Kopyaladıklarınız da burada.")
        case .calendar: String(localized: "Yaklaşan toplantılar ve bugünün anımsatıcıları.")
        case .tools: String(localized: "Not, zamanlayıcı, terminal ve ayna.")
        case .status: String(localized: "Mac'in durumu, Bluetooth aygıtları, Claude limitleri ve CI.")
        case .indicators: String(localized: "Kapalı notch'ta kısa bildirimler ve gizlilik göstergeleri.")
        case .lockScreen: String(localized: "Kilitliyken notch'ta ne görüneceği.")
        case .advanced: String(localized: "Geliştiriciler için ayrıntılar ve belgelenmemiş macOS işlevleri.")
        case .about: String(localized: "Sürüm ve üçüncü taraf yazılımlar.")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .notch: "rectangle.topthird.inset.filled"
        case .permissions: "hand.raised.fill"
        case .now: "house.fill"
        case .shelf: "tray.full.fill"
        case .calendar: "calendar"
        case .tools: "wrench.and.screwdriver.fill"
        case .status: "gauge.with.dots.needle.33percent"
        case .indicators: "bell.badge.fill"
        case .lockScreen: "lock.fill"
        case .advanced: "slider.horizontal.3"
        case .about: "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: .gray
        case .notch: Color(red: 0.2, green: 0.2, blue: 0.24)
        case .permissions: .blue
        case .now: .orange
        case .shelf: .teal
        case .calendar: .red
        case .tools: .indigo
        case .status: .green
        case .indicators: .pink
        case .lockScreen: .purple
        case .advanced: .gray
        case .about: .gray
        }
    }
}

/// Sistem Ayarları gibi renkli kare üstünde beyaz simge.
struct SettingsIcon: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).fill(tint.gradient))
    }
}

/// Sayfanın başı: büyük simge, ad, tek cümle.
struct SettingsPageHeader: View {
    let page: SettingsPage

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(symbol: page.symbol, tint: page.tint, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: page.title).font(.title2.weight(.semibold))
                Text(verbatim: page.subtitle).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension EnvironmentValues {
    /// Aramadan ya da notch'tan gelinen ayar; satırı kısa süre vurgular.
    @Entry var settingsHighlight: String?
}

/// Ayar satırına arama ve doğrudan bağlantı için kimlik; vurgulanınca zemini kısa süre aydınlanır.
private struct SettingsAnchor: ViewModifier {
    let id: String
    @Environment(\.settingsHighlight) private var highlight

    func body(content: Content) -> some View {
        // Gruplu formda satır zemini değiştirilemiyor (listRowBackground etkisiz); vurgu satırın arkasında.
        content
            .id(id)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(highlight == id ? 0.28 : 0))
                    .padding(.horizontal, -8)
                    .padding(.vertical, -5)
            }
            .animation(.easeOut(duration: 0.3), value: highlight == id)
    }
}

extension View {
    func settingsAnchor(_ id: String) -> some View { modifier(SettingsAnchor(id: id)) }
}

/// Özellik açık olsa da notch'un bölüm seçicisinde gösterilsin mi (eski "Bölümler" sekmesi).
struct ShowInNotchToggle: View {
    @Bindable var settings: AppSettings
    let tab: NotchTab
    let isFeatureEnabled: Bool

    var body: some View {
        Toggle(isOn: Binding(
            get: { !settings.hiddenTabs.contains(tab) },
            set: { visible in
                if visible { settings.hiddenTabs.remove(tab) } else { settings.hiddenTabs.insert(tab) }
            })) {
            Text("Notch'ta göster")
        }
        .disabled(!isFeatureEnabled)
        .padding(.leading, 16)
    }
}

/// İznin satır içi gösterimi: ad, neden, durum ve tek düğme. İzin verilmişse sade bir satır.
struct PermissionRow: View {
    let kind: PermissionKind
    let center: PermissionCenter
    var showsIcon = false

    var body: some View {
        let status = center.status(kind)
        HStack(spacing: 10) {
            if showsIcon {
                SettingsIcon(symbol: kind.symbol, tint: kind.tint, size: 24)
            } else {
                Image(systemName: "lock.shield").foregroundStyle(.secondary).frame(width: 16)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: kind.systemName)
                Text(verbatim: kind.purpose).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            StatusPill(status: status)
            if status != .granted {
                Button(status == .notDetermined ? "İzin ver" : "Ayarları aç") { center.request(kind) }
                    .controlSize(.small)
            }
        }
        .settingsAnchor("permission.\(kind.rawValue)")
    }
}

struct StatusPill: View {
    let status: PermissionStatus

    var body: some View {
        Text(verbatim: status.title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(Capsule().fill(color.opacity(0.16)))
    }

    private var color: Color {
        switch status {
        case .granted: .green
        case .denied: .orange
        case .notDetermined: .blue
        case .unknown: .secondary
        }
    }
}

/// Ana düğmenin altındaki kısa açıklama.
struct SettingsNote: View {
    let text: LocalizedStringKey
    var tint: Color = .secondary

    init(_ text: LocalizedStringKey, tint: Color = .secondary) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(text).font(.caption).foregroundStyle(tint).fixedSize(horizontal: false, vertical: true)
    }
}
