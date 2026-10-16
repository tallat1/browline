import AppKit
import Integrations
import QuartzCore
import SwiftUI

/// Çalarken oynayan dört çubuk (boring.notch, Alcove gibi). İki kip:
/// - Yapay: her çubuk farklı süreyle büyüyüp küçülür; ses verisi yok, izin yok.
/// - Müziğe tepkili (ayar, varsayılan kapalı): `AudioSpectrum` bas → tiz dört bandın düzeyini verir,
///   çubuklar saniyede 30 kez ona göre boy alır. Sinyal yoksa (izin verilmedi, sessiz giriş) yapay
///   harekete döner, böylece çubuk hiç donmaz.
///
/// Enerji: yapay kipte animasyon Core Animation katmanında, pencere sunucusunda yürür; uygulama her
/// karede uyanmaz. SwiftUI TimelineView ile 12 kare bile her karede büyük saydam paneli yeniden
/// çizdirdi (ölçüm 2026-10-16: %5,8–16 CPU). Tepkili kipte yalnız dört katmanın boyu değişir
/// (ekran bağlantısı 30 Hz); dinleyici çubuk görünmez olunca bırakılır.
struct EqualizerBars: NSViewRepresentable {
    let isPlaying: Bool
    let tint: Color
    var isEnabled = true
    /// Müziğe tepki için kaynak; nil ise yapay hareket.
    var spectrum: AudioSpectrum?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeNSView(context: Context) -> EqualizerLayerView { EqualizerLayerView() }

    func updateNSView(_ view: EqualizerLayerView, context: Context) {
        view.update(color: NSColor(tint).cgColor, moving: isPlaying && isEnabled && !reduceMotion, spectrum: spectrum)
    }

    static func dismantleNSView(_ view: EqualizerLayerView, coordinator: ()) {
        view.detach()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: EqualizerLayerView, context: Context) -> CGSize? {
        CGSize(width: 18, height: 14)
    }
}

final class EqualizerLayerView: NSView {
    private let bars: [CALayer] = (0..<4).map { _ in CALayer() }
    private var isMoving = false
    private var isAnimating = false
    private var spectrum: AudioSpectrum?
    /// Bu görünüm dinleyiciyi tutuyor mu (her `acquire` bir `release`).
    private var heldSpectrum: AudioSpectrum?
    private var link: CADisplayLink?
    /// Durağan yükseklikler (en yüksek çubuğa oranla) ve her çubuğun salınım süresi.
    private static let resting: [CGFloat] = [0.45, 0.85, 0.6, 0.35]
    private static let durations: [CFTimeInterval] = [0.47, 0.61, 0.53, 0.69]
    private static let barWidth: CGFloat = 2.5
    private static let spacing: CGFloat = 2
    /// Tepkili kipte en kısa boy: sessiz anda çubuk kaybolmasın.
    private static let floor: CGFloat = 0.18

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
        if !isMoving { applyResting() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateReactive()
    }

    func update(color: CGColor, moving: Bool, spectrum: AudioSpectrum?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bars.forEach { $0.backgroundColor = color }
        CATransaction.commit()
        self.spectrum = spectrum
        if moving != isMoving {
            isMoving = moving
            if moving { startAnimations() } else { stopAnimations() }
        }
        updateReactive()
    }

    /// Görünümden kalkınca dinleyici bırakılır.
    func detach() {
        spectrum = nil
        updateReactive()
    }

    /// Tepkili kip: çalıyor, pencerede ve kaynak var. Kaynak değişirse eskisi bırakılır.
    private func updateReactive() {
        let wanted = isMoving && window != nil ? spectrum : nil
        guard wanted !== heldSpectrum else { return }
        heldSpectrum?.release()
        heldSpectrum = wanted
        wanted?.acquire()
        if wanted != nil {
            let link = displayLink(target: self, selector: #selector(tick))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 20, maximum: 30, preferred: 30)
            link.add(to: .main, forMode: .common)
            self.link = link
        } else {
            link?.invalidate()
            link = nil
            if isMoving, !isAnimating { startAnimations() }
        }
    }

    @objc private func tick() {
        guard let spectrum = heldSpectrum else { return }
        let reading = spectrum.levels.read()
        guard reading.hasSignal else {
            // İzin yok ya da sessiz: yapay harekete dön.
            if !isAnimating { startAnimations() }
            return
        }
        if isAnimating { removeAnimations() }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (bar, level) in zip(bars, reading.values) {
            let scale = Self.floor + (1 - Self.floor) * CGFloat(level)
            bar.transform = CATransform3DMakeScale(1, scale, 1)
        }
        CATransaction.commit()
    }

    private func applyResting() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (bar, scale) in zip(bars, Self.resting) { bar.transform = CATransform3DMakeScale(1, scale, 1) }
        CATransaction.commit()
    }

    private func startAnimations() {
        let now = CACurrentMediaTime()
        applyResting()
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
        isAnimating = true
    }

    private func removeAnimations() {
        bars.forEach { $0.removeAnimation(forKey: "equalizer") }
        isAnimating = false
    }

    private func stopAnimations() {
        removeAnimations()
        applyResting()
    }
}
