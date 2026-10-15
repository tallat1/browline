import AppKit
import SwiftUI

/// Çalarken hafifçe oynayan dört çubuk (boring.notch, Alcove gibi). Ses verisi değil: her çubuk
/// farklı süreyle büyüyüp küçülür, düzenli ama tekdüze olmayan bir hareket.
///
/// Enerji: animasyon Core Animation katmanında, pencere sunucusunda yürür; uygulama her karede
/// uyanmaz. SwiftUI TimelineView ile 12 kare bile her karede büyük saydam paneli yeniden çizdirdi
/// (ölçüm 2026-10-16: %5,8–16 CPU). Duraklatınca, azaltılmış harekette ya da ayar kapalıysa
/// animasyonlar kaldırılır, durağan dalga kalır.
struct EqualizerBars: NSViewRepresentable {
    let isPlaying: Bool
    let tint: Color
    var isEnabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeNSView(context: Context) -> EqualizerLayerView { EqualizerLayerView() }

    func updateNSView(_ view: EqualizerLayerView, context: Context) {
        view.update(color: NSColor(tint).cgColor, moving: isPlaying && isEnabled && !reduceMotion)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: EqualizerLayerView, context: Context) -> CGSize? {
        CGSize(width: 18, height: 14)
    }
}

final class EqualizerLayerView: NSView {
    private let bars: [CALayer] = (0..<4).map { _ in CALayer() }
    private var isMoving = false
    /// Durağan yükseklikler (en yüksek çubuğa oranla) ve her çubuğun salınım süresi.
    private static let resting: [CGFloat] = [0.45, 0.85, 0.6, 0.35]
    private static let durations: [CFTimeInterval] = [0.47, 0.61, 0.53, 0.69]
    private static let barWidth: CGFloat = 2.5
    private static let spacing: CGFloat = 2

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for bar in bars {
            bar.cornerRadius = Self.barWidth / 2
            layer?.addSublayer(bar)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) kullanılmıyor") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let total = CGFloat(bars.count) * Self.barWidth + CGFloat(bars.count - 1) * Self.spacing
        var x = (bounds.width - total) / 2
        for bar in bars {
            // Tam boy çubuk, ortadan ölçeklenir: dalga simgesi gibi simetrik.
            bar.bounds = CGRect(x: 0, y: 0, width: Self.barWidth, height: bounds.height)
            bar.position = CGPoint(x: x + Self.barWidth / 2, y: bounds.midY)
            x += Self.barWidth + Self.spacing
        }
        CATransaction.commit()
        applyResting()
    }

    func update(color: CGColor, moving: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bars.forEach { $0.backgroundColor = color }
        CATransaction.commit()
        guard moving != isMoving else { return }
        isMoving = moving
        if moving { startAnimations() } else { stopAnimations() }
    }

    private func applyResting() {
        guard !isMoving else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (bar, scale) in zip(bars, Self.resting) { bar.transform = CATransform3DMakeScale(1, scale, 1) }
        CATransaction.commit()
    }

    private func startAnimations() {
        let now = CACurrentMediaTime()
        for (index, bar) in bars.enumerated() {
            let animation = CABasicAnimation(keyPath: "transform.scale.y")
            animation.fromValue = 0.22
            animation.toValue = 1.0
            animation.duration = Self.durations[index]
            animation.autoreverses = true
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            // Çubuklar aynı anda değil, kaydırılmış başlar.
            animation.beginTime = now - Double(index) * 0.17
            bar.add(animation, forKey: "equalizer")
        }
    }

    private func stopAnimations() {
        bars.forEach { $0.removeAnimation(forKey: "equalizer") }
        applyResting()
    }
}
