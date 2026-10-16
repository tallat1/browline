import NotchShell
import SwiftUI

/// Açık notch'un görsel dili: tek yazı ölçeği, tek kart, tek düğme ailesi. Yeni ekran buradan
/// kurulur; sayılar dağılmasın diye görünümlerde sabit ölçü yazılmaz.
enum NotchDesign {
    // Yazı ölçeği (pt): başlık 13 · gövde 12 · ikincil 11 · büyük rakam 30.
    static let title = Font.system(size: 13, weight: .semibold)
    static let body = Font.system(size: 12)
    static let bodyEmphasized = Font.system(size: 12, weight: .semibold)
    static let caption = Font.system(size: 11)
    static let captionEmphasized = Font.system(size: 11, weight: .semibold)
    static let figure = Font.system(size: 30, weight: .semibold).monospacedDigit()

    static let cardFill = Color.white.opacity(0.06)
    static let cardHoverFill = Color.white.opacity(0.10)
    static let selectionFill = Color.white.opacity(0.14)
    static let track = Color.white.opacity(0.15)

    static let cardRadius: CGFloat = 12
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
    /// İçerik kartı: yumuşak dolgu, 12 pt köşe.
    func notchCard(padding: EdgeInsets = NotchDesign.cardPadding) -> some View {
        self.padding(padding)
            .background(RoundedRectangle(cornerRadius: NotchDesign.cardRadius, style: .continuous)
                .fill(NotchDesign.cardFill))
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
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)
            Text(title).font(NotchDesign.bodyEmphasized)
            if let message {
                Text(message)
                    .font(NotchDesign.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            action().padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension EmptyStateView where Action == EmptyView {
    init(symbol: String, title: LocalizedStringKey, message: LocalizedStringKey? = nil) {
        self.init(symbol: symbol, title: title, message: message) { EmptyView() }
    }
}

/// Kapsül düğme: ikincil eylemler (+1 dk, İptal, AirDrop). Üzerine gelince aydınlanır.
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
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .font(NotchDesign.captionEmphasized)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 12)
                .frame(minHeight: 26)
                .background(Capsule().fill(fill))
                .foregroundStyle(prominent ? tint : .white)
                .contentShape(Capsule())
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .onHover { isHovering = $0 }
                .notchAnimation(NotchMotion.hover, value: isHovering)
        }

        private var fill: Color {
            if prominent { return tint.opacity(isHovering ? 0.32 : 0.22) }
            return isHovering ? NotchDesign.cardHoverFill.opacity(1.6) : NotchDesign.selectionFill.opacity(0.75)
        }
    }
}

/// Simge düğmesi: medya kontrolleri gibi; üzerine gelince yuvarlak zemin belirir.
struct IconButtonStyle: ButtonStyle {
    var size: CGFloat = 32

    func makeBody(configuration: Configuration) -> some View {
        IconButtonBody(configuration: configuration, size: size)
    }

    private struct IconButtonBody: View {
        let configuration: Configuration
        let size: CGFloat
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .frame(width: size, height: size)
                .background(Circle().fill(Color.white.opacity(isHovering ? 0.12 : 0)))
                .contentShape(Circle())
                .scaleEffect(configuration.isPressed ? 0.9 : 1)
                .onHover { isHovering = $0 }
                .notchAnimation(NotchMotion.hover, value: isHovering)
        }
    }
}
