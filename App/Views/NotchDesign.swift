import NotchShell
import SwiftUI

/// Açık notch'un tasarım sistemi (2026-10-16 modernizasyon turu). Tüm ekranlar buradan kurulur;
/// görünümlerde sabit ölçü, renk ya da süre yazılmaz. Gövde hep siyah; yüzeyler beyazın düşük
/// opaklıklarıyla katmanlanır (koyu kipte native macOS yardımcı uygulamaları gibi).
enum NotchDesign {
    // MARK: Yazı ölçeği (pt): büyük rakam 24 · başlık 13 · gövde 12 · ikincil 11 · mikro 10
    /// Kart içindeki ana sayı (yüzde, bellek): yuvarlatılmış, eşit genişlikte rakam.
    static let hero = Font.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit()
    static let title = Font.system(size: 13, weight: .semibold)
    static let body = Font.system(size: 12)
    static let bodyEmphasized = Font.system(size: 12, weight: .semibold)
    static let caption = Font.system(size: 11)
    static let captionEmphasized = Font.system(size: 11, weight: .semibold)
    static let micro = Font.system(size: 10, weight: .medium)
    /// Zamanlayıcının büyük geri sayımı.
    static let figure = Font.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit()

    // MARK: Boşluk ölçeği
    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 6
        static let m: CGFloat = 8
        static let l: CGFloat = 12
        static let xl: CGFloat = 16
    }

    // MARK: Köşe yarıçapı
    enum Radius {
        /// Simge düğmesi zemini, satır vurgusu.
        static let small: CGFloat = 7
        /// Yan kartlar, ayrıntı kutusu.
        static let medium: CGFloat = 10
        /// İçerik kartı.
        static let large: CGFloat = 12
    }

    // MARK: Simge ölçüleri: ince ağırlık, tek hizalama kutusu
    enum Icon {
        static let small: CGFloat = 11
        static let regular: CGFloat = 13
        static let large: CGFloat = 15
        static let weight: Font.Weight = .medium
    }

    // MARK: Kontrol yükseklikleri
    enum Control {
        static let small: CGFloat = 22
        static let regular: CGFloat = 26
        static let large: CGFloat = 32
    }

    // MARK: Yüzeyler ve kenarlık (siyah gövde üstünde)
    /// Yüzey 1: içerik kartı.
    static let cardFill = Color.white.opacity(0.06)
    /// Üzerine gelinen kart ya da satır.
    static let cardHoverFill = Color.white.opacity(0.10)
    /// Seçili sekme, seçili çip.
    static let selectionFill = Color.white.opacity(0.14)
    /// Basılı kontrol.
    static let pressedFill = Color.white.opacity(0.18)
    /// Kartların ince kenarı: siyah üstünde yüzeyi ayırır, ağır gölge yerine.
    static let hairline = Color.white.opacity(0.07)
    static let track = Color.white.opacity(0.14)
    /// İkincil üst bilgi (güncellenme zamanı, kaynak): ikincilden bir kademe sönük ama okunur.
    static let metadata = Color.white.opacity(0.5)
    /// Pasif kontrol opaklığı.
    static let disabledOpacity: Double = 0.4
    /// Seçili olmayan sekme simgesi ve üzerine gelinince.
    static let inactiveIconOpacity: Double = 0.45
    static let hoverIconOpacity: Double = 0.8

    static let cardRadius: CGFloat = Radius.large
    static let cardPadding = EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)

    /// Açık notch'un genişliği: tüm sekmelerde aynı (geçişte yana zıplama yok).
    static let openWidth: CGFloat = 640
    /// Bant (sekmeler + durum) ile içerik arası.
    static let headerSpacing: CGFloat = 6
    /// Banttaki sekme simgesi ve aralığı.
    static let tabIconSize: CGFloat = 24
    static let tabIconSpacing: CGFloat = 2
}

extension View {
    /// İçerik kartı: yumuşak dolgu, ince kenar, 12 pt köşe.
    func notchCard(padding: EdgeInsets = NotchDesign.cardPadding) -> some View {
        self.padding(padding)
            .background(RoundedRectangle(cornerRadius: NotchDesign.cardRadius, style: .continuous)
                .fill(NotchDesign.cardFill))
            .overlay(RoundedRectangle(cornerRadius: NotchDesign.cardRadius, style: .continuous)
                .strokeBorder(NotchDesign.hairline, lineWidth: 0.5))
    }
}

/// Ölçüm kartı (Claude limitleri, işlemci, bellek): üstte etiket ve sağda bağlam (ör. sıfırlanma),
/// ortada büyük değer ve küçük birim, altta ince çubuk. Bilgi tek bakışta: önce sayı, sonra bağlam.
struct MetricCard: View {
    let title: LocalizedStringKey
    let value: String
    var unit: String?
    /// 0…1; nil ise çubuk yok.
    var level: Double?
    var tint: Color = .white
    /// Sağ üstte kısa bağlam ve tam açıklaması (üzerine gelince).
    var context: String?
    var contextSymbol: String?
    var contextHelp: String?

    var body: some View {
        VStack(alignment: .leading, spacing: NotchDesign.Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: NotchDesign.Space.s) {
                Text(title).font(NotchDesign.captionEmphasized).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: NotchDesign.Space.s)
                if let context {
                    HStack(spacing: 3) {
                        if let contextSymbol {
                            Image(systemName: contextSymbol).font(.system(size: 9, weight: .semibold))
                        }
                        Text(verbatim: context).monospacedDigit()
                    }
                    .font(NotchDesign.caption)
                    .foregroundStyle(NotchDesign.metadata)
                    .lineLimit(1)
                    .help(contextHelp ?? context)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: NotchDesign.Space.xs) {
                Text(verbatim: value)
                    .font(NotchDesign.hero)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                    .notchAnimation(value: value)
                if let unit {
                    Text(verbatim: unit).font(NotchDesign.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            if let level {
                LevelBar(level: level, tint: tint).frame(height: 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .notchCard()
    }
}

/// Üst bilgi satırı: küçük simge + metin, sıkı aralık.
struct MetadataLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: NotchDesign.Space.xs) {
            configuration.icon.font(.system(size: 9, weight: .semibold))
            configuration.title
        }
    }
}

/// Kart başlığı: küçük, ikincil renkli etiket.
struct CardLabel: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text).font(NotchDesign.captionEmphasized).foregroundStyle(.secondary)
    }
}

/// Boş durum: simge, başlık, tek satır açıklama ve isteğe bağlı eylem. Özür değil davet.
struct EmptyStateView<Action: View>: View {
    let symbol: String
    let title: LocalizedStringKey
    var message: LocalizedStringKey?
    @ViewBuilder var action: () -> Action

    var body: some View {
        VStack(spacing: NotchDesign.Space.s) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.tertiary)
                .padding(.bottom, NotchDesign.Space.xxs)
            Text(title).font(NotchDesign.bodyEmphasized)
            if let message {
                Text(message)
                    .font(NotchDesign.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            action().padding(.top, NotchDesign.Space.xs)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension EmptyStateView where Action == EmptyView {
    init(symbol: String, title: LocalizedStringKey, message: LocalizedStringKey? = nil) {
        self.init(symbol: symbol, title: title, message: message) { EmptyView() }
    }
}

/// Kapsül düğme: ikincil eylemler (+1 dk, İptal, AirDrop). Durumlar: üzerine gelme, basılı, pasif.
struct CapsuleButtonStyle: ButtonStyle {
    var prominent = false
    var tint: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        CapsuleButtonBody(configuration: configuration, prominent: prominent, tint: tint)
    }

    private struct CapsuleButtonBody: View {
        let configuration: Configuration
        let prominent: Bool
        let tint: Color
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .font(NotchDesign.captionEmphasized)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, NotchDesign.Space.l)
                .frame(minHeight: NotchDesign.Control.regular)
                .background(Capsule().fill(fill))
                .foregroundStyle(prominent ? tint : .white)
                .contentShape(Capsule())
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .opacity(isEnabled ? 1 : NotchDesign.disabledOpacity)
                .onHover { isHovering = $0 && isEnabled }
                .notchAnimation(NotchMotion.hover, value: isHovering)
                .notchAnimation(NotchMotion.press, value: configuration.isPressed)
        }

        private var fill: Color {
            if prominent { return tint.opacity(configuration.isPressed ? 0.38 : (isHovering ? 0.3 : 0.2)) }
            if configuration.isPressed { return NotchDesign.pressedFill }
            return isHovering ? NotchDesign.selectionFill : NotchDesign.cardHoverFill
        }
    }
}

/// Simge düğmesi: medya kontrolleri gibi; üzerine gelince yuvarlak zemin, basılınca koyulaşır.
struct IconButtonStyle: ButtonStyle {
    var size: CGFloat = 32

    func makeBody(configuration: Configuration) -> some View {
        IconButtonBody(configuration: configuration, size: size)
    }

    private struct IconButtonBody: View {
        let configuration: Configuration
        let size: CGFloat
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .frame(width: size, height: size)
                .background(Circle().fill(configuration.isPressed ? NotchDesign.pressedFill
                                          : (isHovering ? NotchDesign.cardHoverFill : .clear)))
                .contentShape(Circle())
                .scaleEffect(configuration.isPressed ? 0.92 : 1)
                .opacity(isEnabled ? 1 : NotchDesign.disabledOpacity)
                .onHover { isHovering = $0 && isEnabled }
                .notchAnimation(NotchMotion.hover, value: isHovering)
                .notchAnimation(NotchMotion.press, value: configuration.isPressed)
        }
    }
}

extension TimelineView.Context {
    /// Hesaplarda kullanılacak an. `.everyMinute` ilk kaydı dakikanın başına (geçmişe) tarihliyor:
    /// notch her açılışta görünüm yeniden kurulduğu için kalan/geçen dakikalar bir fazla çıkıyordu
    /// (2026-10-16: 30 dk uyanık tutma "31 dk").
    var currentDate: Date { max(date, .now) }
}


