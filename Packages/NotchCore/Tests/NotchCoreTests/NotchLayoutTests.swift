import CoreGraphics
import Testing
@testable import NotchShell

/// Faz 0'da 16" MacBook Pro / macOS 27.0.1 üzerinde ölçülen değerler.
struct NotchLayoutTests {
    /// 1728×1117 varsayılan ölçek: safeTop 32, çentik 185×32 @ x=771,5, menü çubuğu 33.
    static let builtInDefault = ScreenMetrics(
        displayID: 1, name: "Yerleşik", isBuiltIn: true,
        frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
        visibleFrame: CGRect(x: 0, y: 0, width: 1728, height: 1084),
        safeAreaTop: 32,
        auxiliaryTopLeft: CGRect(x: 0, y: 1085, width: 771.5, height: 32),
        auxiliaryTopRight: CGRect(x: 956.5, y: 1085, width: 771.5, height: 32))

    @Test func notchRectComesFromAuxiliaryAreas() throws {
        let notch = try #require(Self.builtInDefault.notchRect)
        #expect(notch == CGRect(x: 771.5, y: 1085, width: 185, height: 32))
        #expect(Self.builtInDefault.menuBarHeight == 33)
    }

    @Test func belowNotchResolutionFallsBackToPill() {
        var metrics = Self.builtInDefault
        metrics.safeAreaTop = 0
        metrics.auxiliaryTopLeft = nil
        metrics.auxiliaryTopRight = nil
        let layout = NotchLayout.make(metrics: metrics)
        #expect(layout.style == .pill)
        #expect(layout.notchRect == nil)
    }

    @Test func closedShapeCoversNotchWithEars() {
        let layout = NotchLayout.make(metrics: Self.builtInDefault)
        let closed = layout.shapeRect(for: .closed)
        #expect(layout.style == .notch)
        #expect(closed.width == 185 + 2 * NotchLayout.closedTopRadius)
        #expect(closed.height == 32)
        #expect(closed.midX == 771.5 + 185 / 2)
        #expect(closed.maxY == 1117)
    }

    @Test func panelContainsEveryPresentation() {
        let layout = NotchLayout.make(metrics: Self.builtInDefault)
        for presentation in [NotchPresentation.closed, .compact, .peek(compact: true), .peek(compact: false), .open] {
            #expect(layout.panelFrame.contains(layout.shapeRect(for: presentation)))
        }
    }

    @Test func compactAddsWings() {
        let layout = NotchLayout.make(metrics: Self.builtInDefault)
        let wings = 2 * layout.config.compactWingWidth
        #expect(layout.size(for: .compact).width == layout.closedSize.width + wings)
    }

    /// Geniş kanat açık genişliği aşamaz; panel karesi hiç değişmez.
    @Test func wideWingIsClampedInsidePanel() {
        let layout = NotchLayout.make(metrics: Self.builtInDefault)
        let wide = layout.shapeRect(for: .compact, wingWidth: 128)
        #expect(wide.width == layout.closedSize.width + 256)
        let huge = layout.shapeRect(for: .peek(compact: true), wingWidth: 10_000)
        #expect(layout.panelFrame.contains(huge))
    }

    /// Çoklu ekran: yerleşik ekran (0,0)'da değilken konum yardımcı alanlardan gelmeli.
    @Test func offsetScreenKeepsNotchCentered() throws {
        var metrics = Self.builtInDefault
        metrics.frame.origin = CGPoint(x: -1728, y: 200)
        metrics.auxiliaryTopLeft = CGRect(x: -1728, y: 1285, width: 771.5, height: 32)
        metrics.auxiliaryTopRight = CGRect(x: -771.5, y: 1285, width: 771.5, height: 32)
        let layout = NotchLayout.make(metrics: metrics)
        let notch = try #require(layout.notchRect)
        #expect(notch.minX == -956.5)
        #expect(layout.panelFrame.midX == notch.midX)
        #expect(layout.panelFrame.maxY == 1317)
    }
}
