import SwiftUI

/// Tek hareket sistemi: kabuk ve uygulama aynı eğrileri kullanır. Hepsi aynı yay ailesinden;
/// bir animasyon sürerken yenisi gelirse SwiftUI yayı hızı devralarak birleştirir, sıçrama olmaz.
/// Boring.notch'ta 0,8 sönümün aşması şikâyet topladı; açılış ve kapanış kritik sönümlü.
public enum NotchMotion {
    // Süreler 2026-10-16 modernizasyonunda kısaltıldı (100–250 ms hedefi; yaylar algısal süre).
    /// Açılış: kritik sönümlü, 0,32 sn.
    public static let open = Animation.spring(duration: 0.32, bounce: 0)
    /// Kapanış: açılıştan biraz kısa; kapanan şey dikkat çekmesin.
    public static let close = Animation.spring(duration: 0.28, bounce: 0)
    /// Kompakt kanat genişliği ve sekmeye göre boy değişimi: çok hafif esnek.
    public static let resize = Animation.spring(duration: 0.3, bounce: 0.04)
    /// İçerik değişimi (şarkı, etkinlik, kapak, sekme): kısa çapraz geçiş.
    public static let content = Animation.easeInOut(duration: 0.2)
    /// Hareketi azalt açıkken boyut animasyonu yerine yalnız saydamlık.
    public static let reducedMotion = Animation.easeInOut(duration: 0.15)
    /// Üzerine gelme geri bildirimi (düğme zemini, kalınlaşan çubuk): anlık ama sert değil.
    public static let hover = Animation.easeOut(duration: 0.12)
    /// Basılma: en kısa geri bildirim.
    public static let press = Animation.easeOut(duration: 0.08)
    /// Panel görünür/gizli (yüzen kart, boştaki hap, tam ekran, kilit): pencere saydamlığı.
    public static let panelFadeDuration: TimeInterval = 0.16

    /// Kayan yazı: sabit hız (pt/sn), başlamadan ve sonda bekleme.
    public static let marqueeSpeed: Double = 30
    public static let marqueeStartDelay: TimeInterval = 0.9
    public static let marqueeEndPause: TimeInterval = 1.2
    /// Sonda bekledikten sonra başa dönüş.
    public static let marqueeReturn = Animation.easeInOut(duration: 0.45)

    /// Kayan yazının bir turu (başlama beklemesi + kayma + son bekleme + dönüş), saniye.
    /// Kısa bildirimin süresi buna göre uzatılır ki ad sonuna kadar okunabilsin.
    public static func marqueeCycle(overflow: Double) -> TimeInterval {
        guard overflow > 0 else { return 0 }
        return marqueeStartDelay + overflow / marqueeSpeed + marqueeEndPause + 0.45
    }
}

extension EnvironmentValues {
    /// Sürekli hareket (kayan yazı, çalarken oynayan çubuklar) duraklasın mı: Düşük Güç Modu'nda
    /// (ayar açıksa) true. Kısa geçişler sürer; macOS da bu modda yalnız sürekli işleri kısar.
    @Entry public var pausesContinuousMotion = false
}

/// Geçiş türleri. Hareketi azalt açıkken hepsi yalnız saydamlığa iner.
public enum NotchTransition: Sendable {
    /// İçerik değişimi (sekme, durum): saydamlık + çok hafif ölçek.
    case swap
    /// Listeye eklenen/çıkan öğe: saydamlık + yukarıdan kısa kayma.
    case listItem
    /// Yalnız saydamlık (durum çipleri, küçük öğeler).
    case fade

    var transition: AnyTransition {
        switch self {
        case .swap: .opacity.combined(with: .scale(scale: 0.98))
        case .listItem: .opacity.combined(with: .move(edge: .top))
        case .fade: .opacity
        }
    }
}

extension View {
    /// Ürün genelinde tek geçiş dili; azaltılmış hareket tercihine uyar.
    public func notchTransition(_ kind: NotchTransition = .swap) -> some View {
        modifier(NotchTransitionModifier(kind: kind))
    }

    /// Ürün genelinde tek animasyon dili; azaltılmış harekette kısa bir saydamlık geçişine iner.
    public func notchAnimation<Value: Equatable>(_ animation: Animation = NotchMotion.content, value: Value) -> some View {
        modifier(NotchAnimationModifier(animation: animation, value: value))
    }
}

private struct NotchTransitionModifier: ViewModifier {
    let kind: NotchTransition
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transition(reduceMotion ? .opacity : kind.transition)
    }
}

private struct NotchAnimationModifier<Value: Equatable>: ViewModifier {
    let animation: Animation
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? NotchMotion.reducedMotion : animation, value: value)
    }
}
