import Foundation
import Observation
import PrivateBridges

/// Ekran kaydediliyor ya da paylaşılıyor mu (QuickTime, ⌘⇧5, toplantıda ekran paylaşımı, AirPlay).
/// İzin istemez; bildirim olmadığı için 2 sn'de bir sorulur (tek, ucuz çağrı; zamanlayıcı esnek).
@MainActor
@Observable
public final class ScreenRecordingMonitor {
    public private(set) var isRecording = false
    /// Kaydın başladığı an (kompakt kanatta geçen süre).
    public private(set) var startedAt: Date?
    @ObservationIgnored public var onChange: ((Bool) -> Void)?
    @ObservationIgnored private var timer: DispatchSourceTimer?

    public init() {}

    public var isAvailable: Bool { ScreenWatcher.isAvailable }

    public func start() {
        guard timer == nil, isAvailable else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .seconds(2), leeway: .seconds(1))
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.resume()
        self.timer = timer
    }

    public func stop() {
        timer?.cancel()
        timer = nil
        update(false)
    }

    private func refresh() {
        update(ScreenWatcher.isPresent() ?? false)
    }

    private func update(_ recording: Bool) {
        guard recording != isRecording else { return }
        isRecording = recording
        startedAt = recording ? .now : nil
        onChange?(recording)
    }
}
