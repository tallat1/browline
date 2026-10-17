import ActivityAPI
import ActivityEngine
import AppKit
import Integrations
import NotchShell
import Observation
import SwiftUI

/// Ayarlar değişince servisleri açar, kapatır ve yeniden yapılandırır (idempotent).
extension AppCoordinator {
    /// Ayarlar her değiştiğinde idempotent olarak uygulanır.
    func applySettings() {
        panels.options = settings.panelOptions
        toggle(settings.nowPlayingEnabled, start: nowPlaying.start, stop: nowPlaying.stop)
        // Terminal sekme açılınca başlar; modül kapatılınca kabuk sonlanır.
        if !settings.terminalEnabled { terminal.stop() }
        toggle(settings.clipboardEnabled, start: clipboard.start, stop: clipboard.stop)
        toggle(settings.batteryEnabled, start: battery.start, stop: battery.stop)
        toggle(settings.calendarEnabled, start: calendar.start, stop: calendar.stop)
        setActivityAPI(enabled: settings.activityAPIEnabled)
        toggle(settings.privacyIndicatorEnabled, start: privacy.start, stop: privacy.stop)
        toggle(settings.screenRecordingIndicatorEnabled, start: screenRecording.start, stop: screenRecording.stop)
        if settings.ciEnabled {
            ci.start(repositories: settings.ciRepositories, onlyMine: settings.ciOnlyMine)
        } else {
            ci.stop()
        }
        toggle(settings.downloadsEnabled, start: downloads.start, stop: downloads.stop)
        toggle(settings.audioOutputAlertEnabled, start: audioOutput.start, stop: audioOutput.stop)
        toggle(settings.bluetoothEnabled, start: bluetooth.start, stop: bluetooth.stop)
        toggle(settings.meetingControlsEnabled, start: microphone.start, stop: microphone.stop)
        updateMicShortcut()
        updateSpectrum()
        updateLockWidget()
        updatePrivacyActivity()
        toggle(settings.calendarEnabled && settings.remindersEnabled, start: reminders.start, stop: reminders.stop)
        // Modül açıkken arka planda seyrek örnekleme: Sistem sayfası açılınca grafik geçmişi hazır.
        toggle(settings.systemStatsEnabled, start: systemStats.startBackground, stop: systemStats.stop)
        toggle(settings.claudeUsageEnabled, start: claudeUsage.start, stop: claudeUsage.stop)
        if settings.weatherEnabled, let place = settings.weatherPlace { weather.start(place: place) } else { weather.stop() }
        if !settings.keepAwakeEnabled { keepAwake.stop() }
        if !settings.timerEnabled { cancelTimer() }
        if !settings.trackPeekEnabled { activities.cancelFlash(ActivityKind.trackChange) }
        hud.setMode(settings.hudMode)
        lockScreen.setLayoutConfig(settings.panelOptions.layout)
        lockScreen.setEnabled(settings.lockScreenEnabled)
        if !settings.nowPlayingEnabled { activities.removeLive(ActivityKind.nowPlaying) }
        if !settings.calendarEnabled { activities.removeLive(ActivityKind.meeting) }
        if !settings.batteryEnabled { activities.cancelFlash(ActivityKind.power) }
        if !availablePages.contains(ui.selectedPage), let first = availablePages.first { ui.selectedPage = first }
        questions.isEnabled = settings.activityAPIEnabled
            && (settings.questionsEnabled || settings.choiceQuestionsEnabled || settings.decisionCardsEnabled)
        questions.acceptsApprovals = settings.questionsEnabled
        questions.acceptsChoices = settings.choiceQuestionsEnabled
        questions.acceptsHandoffs = settings.decisionCardsEnabled
        // Kapatılan türün bekleyen soruları "yanıt yok"la çözülür: istemci kendi akışına döner.
        for question in questions.questions where !questions.accepts(question) { questions.answer(question.id, with: nil) }
    }

    private func toggle(_ enabled: Bool, start: () -> Void, stop: () -> Void) {
        if enabled { start() } else { stop() }
    }
    /// Düşük Güç Modu'nda (ayar açıksa) kayan yazı ve çubuklar durur, ses dinleyicisi kapanır.
    var isMotionPaused: Bool { settings.pauseMotionInLowPower && lowPower.isEnabled }

    func updateSpectrum() {
        spectrum.isEnabled = settings.animatedEqualizer && settings.reactiveEqualizer && !isMotionPaused
    }

    /// Kısayol yalnız toplantı denetimi açıkken kayıtlı; değişmediyse yeniden kaydedilmez.
    func updateMicShortcut() {
        let preset = settings.meetingControlsEnabled ? settings.micShortcut : .off
        guard preset != registeredMicShortcut, let micShortcut else { return }
        let registered = micShortcut.register(preset)
        registeredMicShortcut = preset
        ui.micShortcutUnavailable = !registered
        AppLog.coordinator.notice("mikrofon kısayolu: \(preset.rawValue, privacy: .public)\(registered ? "" : " (kaydedilemedi)", privacy: .public)")
    }
}
