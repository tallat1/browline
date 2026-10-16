import AppKit
import NotchShell
import SwiftUI

/// Tek satır metin; alana sığmıyorsa sabit hızla kayarak tamamını gösterir. Kısa metinde hareket
/// yok. Bekle → kay → sonda bekle → yumuşakça başa dön; `loops` ise tekrarlar (açık sekmede).
/// Genişlik NSFont ile ölçülür: yerleşim geçişi gerekmez, titreme olmaz. Hareketi azalt ya da Düşük
/// Güç Modu açıksa kaymaz, sonu üç noktayla kesilir.
struct MarqueeText: View {
    enum Trigger {
        /// Görününce bir kez (ya da `loops` ise sürekli) kayar: kanat ve başlık.
        case automatic
        /// Yalnız imleç üzerindeyken kayar: listelerde aynı anda birçok satır hareket etmesin.
        case hover
    }

    let text: String
    let size: CGFloat
    var weight: Font.Weight = .regular
    var loops = false
    var trigger: Trigger = .automatic
    @State private var offset: CGFloat = 0
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.pausesContinuousMotion) private var pausesContinuousMotion

    private var reduceMotion: Bool { accessibilityReduceMotion || pausesContinuousMotion }

    var body: some View {
        GeometryReader { proxy in
            let available = proxy.size.width
            let overflow = max(0, Self.width(of: text, size: size, weight: weight) - available)
            Group {
                if overflow > 1, !reduceMotion {
                    Text(verbatim: text)
                        .fixedSize()
                        .offset(x: offset)
                        .frame(width: available, alignment: .leading)
                        .mask(fadeMask(atStart: offset < -1, atEnd: offset > -overflow + 1))
                } else {
                    Text(verbatim: text).lineLimit(1).truncationMode(.tail)
                        .frame(width: available, alignment: .leading)
                }
            }
            .frame(height: proxy.size.height)
            .task(id: "\(text)|\(Int(available))|\(reduceMotion)|\(isActive)") { await run(overflow: overflow) }
        }
        .onHover { hovering in if trigger == .hover { isHovering = hovering } }
        .font(.system(size: size, weight: weight))
        .frame(height: ceil(size * 1.3))
        .clipped()
    }

    /// Kenarlarda yumuşak geçiş: metin kesik değil, alandan süzülüyor gibi görünür.
    private func fadeMask(atStart: Bool, atEnd: Bool) -> some View {
        LinearGradient(stops: [
            .init(color: atStart ? .clear : .black, location: 0),
            .init(color: .black, location: 0.06),
            .init(color: .black, location: 0.92),
            .init(color: atEnd ? .clear : .black, location: 1),
        ], startPoint: .leading, endPoint: .trailing)
    }

    private var isActive: Bool { trigger == .automatic || isHovering }

    private func run(overflow: CGFloat) async {
        if trigger == .hover, !isHovering {
            // İmleç çıkınca başa yumuşakça dön.
            withAnimation(NotchMotion.marqueeReturn) { offset = 0 }
            return
        }
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { offset = 0 }
        guard overflow > 1, !reduceMotion else { return }
        let loops = self.loops || trigger == .hover
        repeat {
            try? await Task.sleep(for: .seconds(NotchMotion.marqueeStartDelay))
            guard !Task.isCancelled else { return }
            let duration = overflow / NotchMotion.marqueeSpeed
            withAnimation(.linear(duration: duration)) { offset = -overflow }
            try? await Task.sleep(for: .seconds(duration + NotchMotion.marqueeEndPause))
            guard !Task.isCancelled else { return }
            withAnimation(NotchMotion.marqueeReturn) { offset = 0 }
            try? await Task.sleep(for: .seconds(0.45))
        } while loops && !Task.isCancelled
    }

    /// Metnin tek satırda kapladığı genişlik (pt).
    static func width(of text: String, size: CGFloat, weight: Font.Weight) -> CGFloat {
        let font = NSFont.systemFont(ofSize: size, weight: weight.nsWeight)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }
}

private extension Font.Weight {
    var nsWeight: NSFont.Weight {
        switch self {
        case .semibold: .semibold
        case .bold: .bold
        case .medium: .medium
        case .light: .light
        default: .regular
        }
    }
}
