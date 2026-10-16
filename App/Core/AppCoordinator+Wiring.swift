import ActivityAPI
import ActivityEngine
import AppKit
import Integrations
import NotchShell
import Observation
import SwiftUI

/// Servislerin geri çağrılarını etkinlik merkezine ve arayüz durumuna bağlar. `start()` sırayla çağırır;
/// yalnız geri çağrı atar, servisi başlatmaz (ayarlar `applySettings()`'te).
extension AppCoordinator {
    func wireCore() {
        micShortcut = GlobalShortcut(id: 1) { [weak self] in self?.toggleMicrophoneFromShortcut() }
        lowPower.onChange = { [weak self] enabled in
            guard let self else { return }
            AppLog.coordinator.notice("Düşük Güç Modu: \(enabled ? "açık" : "kapalı", privacy: .public)")
            updateSpectrum()
        }
        lowPower.start()
        activities.onActivitiesChanged = { [weak self] in self?.updateCompactState() }
        activities.onCurrentChanged = { activity in
            AppLog.coordinator.notice("öne çıkan etkinlik: \(activity?.id.rawValue ?? "yok", privacy: .public)")
        }
        panels.onModelsChanged = { [weak self] models in
            guard let self else { return }
            for model in models {
                model.onHorizontalSwipe = { [weak self] forward in self?.horizontalSwipe(forward: forward) }
                model.onFileDrop = { [weak self] pasteboard in self?.receiveDroppedFiles(pasteboard) ?? false }
            }
            updateCompactState()
        }
        settings.onChange = { [weak self] in self?.applySettings() }
        lockScreen.onLockChanged = { [weak self] locked in
            guard let self else { return }
            // Ana panel kilit altında kalır; açık kalmasın ki kilit açılınca raf ya da takvim görünmesin.
            if locked { panels.models.forEach { $0.dismiss() } }
            settings.setLockSessionOpen(locked && lockScreen.status == .ready)
            updateLockWidget()
            updateCompactState()
        }
    }

    func wireMedia() {
        nowPlaying.onInfoChanged = { [weak self] info in
            guard let self else { return }
            if settings.trackPeekEnabled, let info, NowPlayingInfo.isTrackChange(from: lastTrackInfo, to: info) {
                activities.flash(ActivityKind.trackChange, duration: Self.trackPeekDuration(for: info.title))
            }
            lastTrackInfo = info
            // Kilitliyken müzik başlayınca/bitince şerit güncellensin (pil yoksa tek içerik müzik).
            if lockScreen.isLocked { updateLockWidget() }
            // Kompakt kanatlar yalnız çalarken; duraklatılmış parça açık notch'ta görünmeye devam eder.
            // Duraklama hemen değil kısa bir payla kanadı kapatır: şarkı geçişindeki anlık duraklama
            // notch'u kapatıp yeniden açmasın.
            if info?.isPlaying == true {
                nowPlayingRemovalTask?.cancel()
                nowPlayingRemovalTask = nil
                activities.setLive(ActivityKind.nowPlaying, priority: 30)
            } else if activities.isLive(ActivityKind.nowPlaying), nowPlayingRemovalTask == nil {
                nowPlayingRemovalTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(1200))
                    guard let self, !Task.isCancelled else { return }
                    self.nowPlayingRemovalTask = nil
                    if self.nowPlaying.info?.isPlaying != true { self.activities.removeLive(ActivityKind.nowPlaying) }
                }
            }
        }
        audioOutput.onChange = { [weak self] device in
            guard let self else { return }
            // Az önce bağlandığı gösterilen kulaklık ikinci kez (ses çıkışı olarak) duyurulmaz.
            if let event = ui.bluetoothEvent, event.change == .connected, event.device.name == device.name,
               Date.now.timeIntervalSince(event.date) < 6 { return }
            activities.flash(ActivityKind.audioOutput,
                             duration: Self.readableFlashDuration(base: .seconds(3), text: device.name))
        }
    }

    func wireCalendar() {
        calendar.onImminentMeetingChanged = { [weak self] event in
            guard let self else { return }
            if event != nil {
                activities.setLive(ActivityKind.meeting, priority: 40)
            } else {
                activities.removeLive(ActivityKind.meeting)
            }
        }
    }

    func wireIndicators() {
        battery.onAlert = { [weak self] alert in
            guard let self else { return }
            switch alert {
            case .low: activities.flash(ActivityKind.batteryLow, duration: .seconds(4))
            case .full: activities.flash(ActivityKind.batteryFull, duration: .seconds(4))
            }
        }
        battery.onPowerSourceChanged = { [weak self] old, _ in
            // İlk okuma değişiklik değildir; yalnız fiş takılıp çıkarıldığında göster.
            guard let self, old != nil else { return }
            activities.flash(ActivityKind.power, duration: .seconds(3))
        }
        privacy.onChange = { [weak self] camera, microphone in
            guard let self else { return }
            AppLog.coordinator.notice("gizlilik: kamera \(camera ? "açık" : "kapalı", privacy: .public), mikrofon \(microphone ? "açık" : "kapalı", privacy: .public)")
            self.microphone.refreshInputApps()
            updatePrivacyActivity()
        }
        screenRecording.onChange = { [weak self] recording in
            guard let self else { return }
            AppLog.coordinator.notice("ekran kaydı: \(recording ? "başladı" : "bitti", privacy: .public)")
            // Kamera/mikrofon göstergesinin (15) hemen önünde; müzik ve toplantı önde kalır.
            if recording { activities.setLive(ActivityKind.screenRecording, priority: 16) }
            else { activities.removeLive(ActivityKind.screenRecording) }
        }
        microphone.onChange = { [weak self] in
            guard let self else { return }
            onStatusIconChange?()
            let muted = microphone.isMuted
            let apps = microphone.inputApps.count
            AppLog.coordinator.notice("mikrofon: \(muted ? "sessiz" : "açık", privacy: .public), kullanan \(apps) uygulama")
            updatePrivacyActivity()
        }
        hud.onShow = { [weak self] in
            self?.activities.flash(ActivityKind.hud, priority: 2_000, duration: .milliseconds(1500))
        }
        downloads.onActiveChanged = { [weak self] list in
            guard let self else { return }
            AppLog.coordinator.notice("indirmeler: \(list.count) etkin")
            if list.isEmpty {
                activities.removeLive(ActivityKind.download)
            } else {
                activities.setLive(ActivityKind.download, priority: 25)
            }
        }
        downloads.onFinished = { [weak self] name in
            guard let self else { return }
            AppLog.coordinator.notice("indirme bitti")
            ui.lastFinishedDownload = name
            activities.flash(ActivityKind.downloadDone, duration: .seconds(3))
        }
        bluetooth.onConnected = { [weak self] in self?.flashBluetooth($0, .connected) }
        bluetooth.onDisconnected = { [weak self] in self?.flashBluetooth($0, .disconnected) }
        bluetooth.onLowBattery = { [weak self] device, level in self?.flashBluetooth(device, .lowBattery(level)) }
        keepAwake.onChange = { [weak self] active in
            guard let self else { return }
            if active { activities.setLive(ActivityKind.keepAwake, priority: 5) } else { activities.removeLive(ActivityKind.keepAwake) }
        }
    }

    func wireExternalAPI() {
        externalActivities.onActivitiesChanged = { [weak self] list in self?.syncExternal(list) }
        questions.onQuestionsChanged = { [weak self] list in self?.questionsChanged(list) }
        questions.onResolved = { question, decision, reason in
            let waited = Int(Date.now.timeIntervalSince(question.askedAt).rounded())
            AppLog.coordinator.notice("onay sorusu kapandı: \(reason.rawValue, privacy: .public), karar \(decision?.rawValue ?? "yok", privacy: .public), \(waited) sn (\(question.subtitle ?? "", privacy: .private))")
        }
        externalActivities.onFlash = { [weak self] activity, duration in
            // İstenen süre en az; uzun başlık sonuna kadar kayabilsin diye gerekirse uzar.
            self?.activities.flash(ActivityKind.externalFlash,
                                   duration: Self.readableFlashDuration(base: duration, text: activity.title))
        }
    }

    func wireStatus() {
        ci.onActiveChanged = { [weak self] runs in
            guard let self else { return }
            AppLog.coordinator.notice("CI: \(runs.count) süren çalışma")
            // Müzik ve toplantı önde; boşta kapalı notch'ta süren derleme görünür.
            if runs.isEmpty { activities.removeLive(ActivityKind.ci) } else { activities.setLive(ActivityKind.ci, priority: 12) }
        }
        ci.onRunFinished = { [weak self] run in
            guard let self else { return }
            AppLog.coordinator.notice("CI bitti: \(String(describing: run.state), privacy: .public)")
            ui.lastFinishedRun = run
            let text = run.workflow.isEmpty ? run.repositoryName : "\(run.repositoryName) · \(run.workflow)"
            activities.flash(ActivityKind.ciDone, duration: Self.readableFlashDuration(base: .seconds(4), text: text))
        }
        claudeUsage.onAlert = { [weak self] _ in
            self?.activities.flash(ActivityKind.claudeUsage, duration: .seconds(5))
        }
    }

    func wireTools() {
        timer.onRunningChanged = { [weak self] running in
            guard let self else { return }
            if running { activities.setLive(ActivityKind.timer, priority: 35) } else { activities.removeLive(ActivityKind.timer) }
        }
        timer.onFinished = { [weak self] in
            guard let self else { return }
            // Pomodoro'da sıradaki evre kendiliğinden başlar; bildirim yeni evreyi söyler.
            if let phase = ui.pomodoroPhase {
                let next = Pomodoro.next(after: phase)
                ui.pomodoroPhase = next
                timer.start(seconds: Pomodoro.duration(of: next))
            }
            activities.flash(ActivityKind.timerDone, duration: .seconds(5))
            NSSound(named: "Glass")?.play()
        }
    }
}
