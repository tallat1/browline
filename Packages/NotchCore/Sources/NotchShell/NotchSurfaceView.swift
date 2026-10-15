import SwiftUI

/// Açık içeriğin çentik bandına göre yerleşmesi için gereken ölçüler.
public struct NotchContext: Equatable, Sendable {
    public let style: NotchLayout.Style
    /// Çentik bandının yüksekliği: açık içerikte ilk satır bu bandın iki yanına yerleşir.
    public let bandHeight: CGFloat
    /// Ortadaki çentiğin genişliği; bu aralığa içerik yazılmamalı (çentiksiz ekranda 0).
    public let notchGapWidth: CGFloat
    public let size: CGSize
    /// Çerçeveden yatay boşluk; kulak eğrisini hesaba katar.
    public let horizontalInset: CGFloat
    public let bottomInset: CGFloat
}

/// Notch yüzeyinin kökü: siyah şekil, durumlar arası yay animasyonu ve içerik yuvaları.
/// İçeriğin ne olduğunu bilmez; kompakt kanatları ve açık içeriği uygulama verir.
public struct NotchSurfaceView<Leading: View, Trailing: View, Expanded: View>: View {
    @Bindable private var model: NotchSurfaceModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let compactLeading: () -> Leading
    private let compactTrailing: () -> Trailing
    private let expanded: (NotchContext) -> Expanded


    public init(model: NotchSurfaceModel,
                @ViewBuilder compactLeading: @escaping () -> Leading,
                @ViewBuilder compactTrailing: @escaping () -> Trailing,
                @ViewBuilder expanded: @escaping (NotchContext) -> Expanded) {
        self.model = model
        self.compactLeading = compactLeading
        self.compactTrailing = compactTrailing
        self.expanded = expanded
    }

    public var body: some View {
        let layout = model.layout
        ZStack(alignment: .top) {
            surfaces(layout)
                .padding(.top, layout.topInset)
        }
        .frame(width: layout.panelFrame.width, height: layout.panelFrame.height, alignment: .top)
        .sensoryFeedback(.alignment, trigger: model.hapticTick)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private func surfaces(_ layout: NotchLayout) -> some View {
        let presentation = model.presentation
        if reduceMotion {
            // Hareketi azalt: boyut büyütme yerine iki sabit katman arasında çapraz geçiş.
            let resting: NotchPresentation = model.hasCompactContent ? .compact : .closed
            ZStack(alignment: .top) {
                surface(layout, resting).opacity(model.isOpen ? 0 : 1)
                surface(layout, .open).opacity(model.isOpen ? 1 : 0)
            }
            .animation(NotchMotion.reducedMotion, value: model.isOpen)
            .animation(NotchMotion.reducedMotion, value: model.hasCompactContent)
        } else {
            surface(layout, presentation)
                .animation(model.isOpen ? NotchMotion.open : NotchMotion.close, value: presentation)
                // Kanat genişliği (şarkı adı, dış etkinlik) ve sekme boyu da aynı aileden yayla akar;
                // eskiden kanat genişliği canlandırılmıyor, şarkı değişince şekil sıçrıyordu.
                .animation(NotchMotion.resize, value: model.compactWingWidth)
                .animation(NotchMotion.resize, value: model.preferredOpenSize)
        }
    }

    private func surface(_ layout: NotchLayout, _ presentation: NotchPresentation) -> some View {
        let size = layout.size(for: presentation, wingWidth: model.compactWingWidth, openSize: model.preferredOpenSize)
        let shape = SurfaceShape.make(for: layout, presentation: presentation)
        return ZStack(alignment: .top) {
            shape.fill(Color.black)
            content(layout, presentation, size)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipShape(shape)
        .overlay {
            // Yüzen kart uygulama içeriğinin üstünde durur; ince kenar onu koyu pencerelerden ayırır.
            // Gölge yok: yarı saydam piksel tıklamayı yutar (şeffaf piksel geçişi).
            if layout.style == .floating { shape.stroke(Color.white.opacity(0.14), lineWidth: 1) }
        }
        .contentShape(shape)
        .onHover { model.hoverChanged($0) }
        .onTapGesture { model.tapped() }
    }

    @ViewBuilder
    private func content(_ layout: NotchLayout, _ presentation: NotchPresentation, _ size: CGSize) -> some View {
        switch presentation {
        case .compact, .peek(compact: true):
            let wing = layout.clampedWingWidth(model.compactWingWidth)
            HStack(spacing: 0) {
                compactLeading().frame(width: wing, height: layout.bandHeight)
                Spacer(minLength: 0)
                compactTrailing().frame(width: wing, height: layout.bandHeight)
            }
            .padding(.horizontal, layout.style == .notch ? NotchLayout.closedTopRadius : 8)
            .frame(width: size.width, height: layout.bandHeight)
            .transition(.opacity)
        case .open:
            expanded(NotchContext(style: layout.style, bandHeight: layout.bandHeight,
                                  notchGapWidth: layout.notchGapWidth, size: size,
                                  horizontalInset: layout.openHorizontalInset,
                                  bottomInset: layout.config.contentBottomMargin))
                .frame(width: size.width, height: size.height, alignment: .top)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
        case .closed, .peek(compact: false):
            EmptyView()
        }
    }
}
