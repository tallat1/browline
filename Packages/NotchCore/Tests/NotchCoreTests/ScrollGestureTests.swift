import AppKit
import CoreGraphics
import Testing
@testable import NotchShell

/// Gerçek kaydırma olaylarıyla (CGEvent): atalet, fare tekerleği ve açıkken içerik kaydırması.
@MainActor
struct ScrollGestureTests {
    private func makeModel() -> NotchSurfaceModel {
        let model = NotchSurfaceModel(layout: NotchLayout.make(metrics: NotchLayoutTests.builtInDefault),
                                      displayID: 1, screenName: "Yerleşik")
        model.hapticsEnabled = false
        model.pointerLocation = { CGPoint(x: 100, y: 100) }  // içerik ya da ekranın başka yeri
        return model
    }

    /// Kaydırma olayı: dy < 0 = parmaklar aşağı (doğal kaydırma kapalıyken). phase/momentum CGEvent alanları.
    private func scroll(dy: Int32 = 0, dx: Int32 = 0, phase: Int64? = nil, momentum: Int64? = nil) -> NSEvent {
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0)!
        if let phase { event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase) }
        if let momentum { event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum) }
        return NSEvent(cgEvent: event)!
    }

    private let began: Int64 = 1, changed: Int64 = 2, ended: Int64 = 4

    @Test func fingersDownOpensClosedNotch() {
        let model = makeModel()
        model.scrolled(scroll(dy: -12, phase: began))
        #expect(model.isOpen)
    }

    @Test func momentumAfterGestureIsIgnored() {
        let model = makeModel()
        model.scrolled(scroll(dy: -12, phase: began))
        model.scrolled(scroll(phase: ended))
        model.dismiss()
        // Parmak kalktıktan sonraki atalet notch'u yeniden açmamalı.
        model.scrolled(scroll(dy: -30, momentum: 2))
        #expect(!model.isOpen)
    }

    @Test func contentScrollDoesNotCloseOpenNotch() {
        let model = makeModel()
        model.tapped()
        model.scrolled(scroll(dy: 20, phase: began))
        model.scrolled(scroll(dy: 20, phase: changed))
        #expect(model.isOpen)
    }

    @Test func scrollingUpOverBandClosesOpenNotch() {
        let model = makeModel()
        model.tapped()
        let shape = model.currentShapeRect
        model.pointerLocation = { CGPoint(x: shape.minX + 30, y: shape.maxY - 5) }
        model.scrolled(scroll(dy: 20, phase: began))
        #expect(!model.isOpen)
    }

    @Test func mouseWheelWorksMoreThanOnce() {
        let model = makeModel()
        // Tekerlek aşamasız gelir; eskiden ilk tıktan sonra kilitleniyordu.
        model.scrolled(scroll(dy: -3))
        #expect(model.isOpen)
        model.dismiss()
        model.scrolled(scroll(dy: -3))
        #expect(!model.isOpen)  // aralık dolmadan ikinci tık birleşir
    }

    @Test func horizontalSwipeFiresOnceDespiteMomentum() {
        let model = makeModel()
        model.tapped()
        var swipes = 0
        model.onHorizontalSwipe = { _ in swipes += 1 }
        model.scrolled(scroll(dx: 30, phase: began))
        model.scrolled(scroll(dx: 30, phase: changed))
        model.scrolled(scroll(phase: ended))
        model.scrolled(scroll(dx: 40, momentum: 1))
        model.scrolled(scroll(dx: 40, momentum: 2))
        #expect(swipes == 1)
    }
}
