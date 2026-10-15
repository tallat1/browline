import AppKit
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

    /// Görünen gövde kulak yarıçapı kadar içeride başlar; içerik boşluğu oradan ölçülür.
    @Test func openInsetAccountsForEarRadius() {
        let notch = NotchLayout.make(metrics: Self.builtInDefault)
        #expect(notch.openHorizontalInset == NotchLayout.openTopRadius + notch.config.contentMargin)
        var metrics = Self.builtInDefault
        metrics.safeAreaTop = 0
        #expect(NotchLayout.make(metrics: metrics).openHorizontalInset == notch.config.contentMargin)
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

struct NotchlessVisibilityTests {
    typealias Visibility = PanelManager.NotchlessVisibility

    @Test func alwaysNeverHides() {
        #expect(!Visibility.always.hidesPanel(style: .pill, hasCompactContent: false, isOpen: false))
    }

    @Test func whenActiveHidesOnlyIdlePill() {
        let visibility = Visibility.whenActive
        #expect(visibility.hidesPanel(style: .pill, hasCompactContent: false, isOpen: false))
        #expect(!visibility.hidesPanel(style: .pill, hasCompactContent: true, isOpen: false))
        #expect(!visibility.hidesPanel(style: .pill, hasCompactContent: false, isOpen: true))
        // Çentikli ekranda seçenek etkisiz.
        #expect(!visibility.hidesPanel(style: .notch, hasCompactContent: false, isOpen: false))
    }
}

struct FloatingAndDisplayModeTests {
    typealias Mode = PanelManager.DisplayMode

    /// Yüzen kart çentikli ekranda da menü çubuğunun altında, çentikten bağımsız durur.
    @Test func floatingSitsBelowMenuBar() {
        let layout = NotchLayout.make(metrics: NotchLayoutTests.builtInDefault, floating: true)
        #expect(layout.style == .floating)
        #expect(layout.notchRect == nil)
        #expect(layout.topInset == 33 + NotchLayout.floatingGap)
        let closed = layout.shapeRect(for: .closed)
        #expect(closed.maxY == 1117 - 33 - NotchLayout.floatingGap)
        #expect(closed.midX == 864)
    }

    @Test func floatingHidesWhenIdleRegardlessOfSetting() {
        for visibility in PanelManager.NotchlessVisibility.allCases {
            #expect(visibility.hidesPanel(style: .floating, hasCompactContent: false, isOpen: false))
            #expect(!visibility.hidesPanel(style: .floating, hasCompactContent: true, isOpen: false))
            #expect(!visibility.hidesPanel(style: .floating, hasCompactContent: false, isOpen: true))
        }
    }

    @Test func policyGivesDefaultsAndOverridesWin() {
        let builtIn = PanelManager.DisplayDescriptor(persistentID: "B", isBuiltIn: true)
        let external = PanelManager.DisplayDescriptor(persistentID: "E", isBuiltIn: false)
        #expect(PanelManager.resolveModes(for: [external, builtIn], policy: .builtInOrMain, overrides: [:])
            == [.off, .automatic])
        #expect(PanelManager.resolveModes(for: [external, builtIn], policy: .allScreens, overrides: [:])
            == [.automatic, .automatic])
        #expect(PanelManager.resolveModes(for: [external, builtIn], policy: .builtInOrMain,
                                          overrides: ["E": .floating, "B": .off]) == [.floating, .off])
    }

    /// Kapak kapalı: yerleşik ekran yok, ilk ekran varsayılan alır.
    @Test func clamshellUsesFirstDisplay() {
        let first = PanelManager.DisplayDescriptor(persistentID: "1", isBuiltIn: false)
        let second = PanelManager.DisplayDescriptor(persistentID: "2", isBuiltIn: false)
        #expect(PanelManager.resolveModes(for: [first, second], policy: .builtInOrMain, overrides: [:])
            == [.automatic, .off])
    }

    @Test func gameCategories() {
        #expect(PanelManager.isGameCategory("public.app-category.games"))
        #expect(PanelManager.isGameCategory("public.app-category.board-games"))
        #expect(!PanelManager.isGameCategory("public.app-category.productivity"))
        #expect(!PanelManager.isGameCategory(nil))
    }
}

struct HorizontalSwipeTests {
    @Test func directionFollowsFingersWithNaturalScrolling() {
        #expect(NotchSurfaceModel.horizontalSwipe(deltaX: -12, deltaY: 1, inverted: true) == true)
        #expect(NotchSurfaceModel.horizontalSwipe(deltaX: 12, deltaY: 1, inverted: true) == false)
        #expect(NotchSurfaceModel.horizontalSwipe(deltaX: 12, deltaY: 1, inverted: false) == true)
    }

    @Test func verticalOrTinyIsIgnored() {
        #expect(NotchSurfaceModel.horizontalSwipe(deltaX: 8, deltaY: 10, inverted: true) == nil)
        #expect(NotchSurfaceModel.horizontalSwipe(deltaX: 3, deltaY: 0, inverted: true) == nil)
    }
}

struct EditShortcutTests {
    @Test func commandShortcutsMapToEditActions() {
        #expect(NotchPanel.editAction(for: "c", modifiers: .command) == #selector(NSText.copy(_:)))
        #expect(NotchPanel.editAction(for: "V", modifiers: .command) == #selector(NSText.paste(_:)))
        #expect(NotchPanel.editAction(for: "z", modifiers: [.command, .shift]) == Selector(("redo:")))
        #expect(NotchPanel.editAction(for: "c", modifiers: [.command, .option]) == nil)
        #expect(NotchPanel.editAction(for: "c", modifiers: []) == nil)
        #expect(NotchPanel.editAction(for: "q", modifiers: .command) == nil)
    }
}

struct PreferredOpenSizeTests {
    @Test func requestedSizeIsClampedAndFitsPanel() {
        let layout = NotchLayout.make(metrics: NotchLayoutTests.builtInDefault)
        #expect(layout.clampedOpenSize(nil) == layout.openSize)
        let square = layout.clampedOpenSize(CGSize(width: 400, height: 384))
        #expect(square == CGSize(width: 400, height: 384))
        let huge = layout.clampedOpenSize(CGSize(width: 5000, height: 5000))
        #expect(huge == layout.maxOpenSize)
        let tiny = layout.clampedOpenSize(CGSize(width: 10, height: 10))
        #expect(tiny.width >= layout.closedSize.width + 2 * layout.config.compactWingWidth)
        for size in [square, huge, tiny] {
            #expect(layout.panelFrame.contains(layout.shapeRect(for: .open, openSize: size)))
        }
    }
}
