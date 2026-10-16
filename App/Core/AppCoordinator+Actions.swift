import ActivityAPI
import ActivityEngine
import AppKit
import Integrations
import NotchShell
import Observation
import SwiftUI

/// Kullanıcı ve özellik eylemleri: mikrofon, Bluetooth bildirimi, zamanlayıcı, raf ve medya.
extension AppCoordinator {
    /// Kamera/mikrofon kullanımı ve mikrofon sessizliği. Sessizdeyken müzikten ve toplantıdan önde:
    /// konuştuğunu sanıp sessizde kalınmasın.
    func updatePrivacyActivity() {
        let muted = isMicrophoneMuted
        if privacy.isCameraActive || privacy.isMicrophoneActive || muted {
            activities.setLive(ActivityKind.privacy, priority: muted ? 45 : 15)
        } else {
            activities.removeLive(ActivityKind.privacy)
        }
    }

    var isMicrophoneMuted: Bool { settings.meetingControlsEnabled && microphone.isMuted }
    /// Kısayol: sessize al / aç ve kapalı notch'ta kısa bildirim (hangi uygulama öndeyse olsun).
    func toggleMicrophoneFromShortcut() {
        guard settings.meetingControlsEnabled, microphone.canMute else {
            NSSound.beep()
            return
        }
        microphone.toggleMute()
        let muted = microphone.isMuted
        AppLog.coordinator.notice("mikrofon kısayolu: \(muted ? "sessiz" : "açık", privacy: .public)")
        activities.flash(ActivityKind.microphone, priority: 2_000, duration: .milliseconds(1500))
    }

    /// Bağlanma, ayrılma ve düşük pil; düşük pil biraz daha uzun kalır.
    func flashBluetooth(_ device: BluetoothMonitor.Device, _ change: BluetoothEvent.Change) {
        let kind = switch change {
        case .connected: "bağlandı"
        case .disconnected: "ayrıldı"
        case let .lowBattery(level): "pil %\(level)"
        }
        AppLog.coordinator.notice("bluetooth \(device.kind.rawValue, privacy: .public): \(kind, privacy: .public)")
        ui.bluetoothEvent = BluetoothEvent(device: device, change: change, date: .now)
        let base: Duration = if case .lowBattery = change { .seconds(4) } else { .seconds(3) }
        activities.flash(ActivityKind.bluetooth, duration: Self.readableFlashDuration(base: base, text: device.shortName))
    }
    func startPomodoro() {
        ui.pomodoroPhase = Pomodoro.first
        timer.start(seconds: Pomodoro.duration(of: Pomodoro.first))
    }

    /// Zamanlayıcıyı ve varsa Pomodoro döngüsünü durdurur.
    func cancelTimer() {
        ui.pomodoroPhase = nil
        timer.cancel()
    }

    /// Notch'a bırakılanlar rafa: adresler hemen, dosya sözleri (ekran görüntüsü küçük resmi) yazılınca.
    func receiveDroppedFiles(_ pasteboard: NSPasteboard) -> Bool {
        guard settings.shelfEnabled else { return false }
        FileDrop.receive(from: pasteboard, destination: ShelfStore.promiseDestination()) { [weak self] urls in
            guard let self, !urls.isEmpty else { return }
            AppLog.coordinator.notice("rafa bırakıldı: \(urls.count) dosya")
            shelf.add(urls)
            ui.selectedPage = .shelf
        }
        return true
    }

    /// Açık notch'ta yatay kaydırma: medya sekmesindeyken parça geçişi (Alcove).
    func horizontalSwipe(forward: Bool) {
        guard ui.selectedPage == .now, nowPlaying.info != nil else { return }
        if forward { nowPlaying.nextTrack() } else { nowPlaying.previousTrack() }
        AppLog.coordinator.notice("kaydırma: \(forward ? "sonraki" : "önceki", privacy: .public) parça")
    }
    var nowPlayingSourceDescription: String {
        switch nowPlaying.source {
        case .checking: String(localized: "Now Playing: denetleniyor…")
        case .mediaRemote: String(localized: "Now Playing: MediaRemote (sistem geneli)")
        case let .playerNotifications(reason): String(localized: "Now Playing: Music/Spotify yedeği (\(reason.localizedText))")
        case .off: String(localized: "Now Playing: kapalı")
        }
    }
}
