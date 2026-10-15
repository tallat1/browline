import Testing
@testable import Integrations

struct HUDTests {
    @Test func steppingSnapsToGrid() {
        let step = HUDController.step
        #expect(HUDController.stepped(0.30, by: step, step: step) == 0.3125)
        #expect(HUDController.stepped(0.30, by: -step, step: step) == 0.25)
        #expect(HUDController.stepped(0.5, by: step, step: step) == 0.5625)
        #expect(HUDController.stepped(1, by: step, step: step) == 1)
        #expect(HUDController.stepped(0, by: -step, step: step) == 0)
    }

    @Test func decodesMediaKeyData() {
        // Ses artırma basma: tuş 0, durum 0xA.
        let down = MediaKeyEvent.decode(data1: (0 << 16) | (0xA << 8))
        #expect(down == MediaKeyEvent(keyCode: 0, isDown: true, isRepeat: false))
        // Parlaklık azaltma bırakma: tuş 3, durum 0xB.
        let up = MediaKeyEvent.decode(data1: (3 << 16) | (0xB << 8))
        #expect(up.keyCode == 3 && !up.isDown)
        // Basılı tutma tekrarı.
        #expect(MediaKeyEvent.decode(data1: (1 << 16) | (0xA << 8) | 1).isRepeat)
    }
}
