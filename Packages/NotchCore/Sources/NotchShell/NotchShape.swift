import SwiftUI

/// Donanım çentiğini taklit eden şekil: üstte dışa açılan iki içbükey "kulak", altta iki
/// yuvarlak köşe. İki yarıçap da canlandırılabilir, yay animasyonu sırasında akar.
/// Clean-room yazıldı; GPL projelerden kod alınmadı.
public struct NotchShape: Shape {
    public var topRadius: CGFloat
    public var bottomRadius: CGFloat

    public init(topRadius: CGFloat, bottomRadius: CGFloat) {
        self.topRadius = topRadius
        self.bottomRadius = bottomRadius
    }

    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    public func path(in rect: CGRect) -> Path {
        // Yarıçaplar dikdörtgene sığmazsa şekil kendi üstüne katlanmasın.
        let top = max(0, min(topRadius, rect.width / 4, rect.height / 2))
        let bottom = max(0, min(bottomRadius, (rect.width - 2 * top) / 2, rect.height - top))
        let bodyLeft = rect.minX + top
        let bodyRight = rect.maxX - top

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: bodyLeft, y: rect.minY + top),
                          control: CGPoint(x: bodyLeft, y: rect.minY))
        path.addLine(to: CGPoint(x: bodyLeft, y: rect.maxY - bottom))
        path.addQuadCurve(to: CGPoint(x: bodyLeft + bottom, y: rect.maxY),
                          control: CGPoint(x: bodyLeft, y: rect.maxY))
        path.addLine(to: CGPoint(x: bodyRight - bottom, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: bodyRight, y: rect.maxY - bottom),
                          control: CGPoint(x: bodyRight, y: rect.maxY))
        path.addLine(to: CGPoint(x: bodyRight, y: rect.minY + top))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                          control: CGPoint(x: bodyRight, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// Çentikli ekranda NotchShape, hap ve yüzen kartta yuvarlak dikdörtgen; durumlar arasında yarıçaplar akar.
public struct SurfaceShape: Shape {
    var isPill: Bool
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    public func path(in rect: CGRect) -> Path {
        if isPill {
            return Path(roundedRect: rect, cornerRadius: min(bottomRadius, rect.height / 2), style: .continuous)
        }
        return NotchShape(topRadius: topRadius, bottomRadius: bottomRadius).path(in: rect)
    }

    static func make(for layout: NotchLayout, presentation: NotchPresentation) -> SurfaceShape {
        let open = presentation == .open
        switch layout.style {
        case .notch:
            return SurfaceShape(isPill: false,
                                topRadius: open ? NotchLayout.openTopRadius : NotchLayout.closedTopRadius,
                                bottomRadius: open ? NotchLayout.openBottomRadius : NotchLayout.closedBottomRadius)
        case .pill, .floating:
            let height = layout.size(for: presentation).height
            return SurfaceShape(isPill: true, topRadius: 0,
                                bottomRadius: open ? NotchLayout.pillOpenCornerRadius : height / 2)
        }
    }
}
