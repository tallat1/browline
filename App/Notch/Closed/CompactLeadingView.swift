import ActivityAPI
import ActivityEngine
import Integrations
import NotchShell
import SwiftUI

/// Çentiğin solundaki kanat: etkinliğin simgesi ya da kapağı.
struct CompactLeadingView: View {
    let coordinator: AppCoordinator
    let activityID: ActivityID?

    var body: some View {
        // Etkinlik değişince (çalan → şarkı önizlemesi → çalan) içerik ani değil, çapraz geçişle.
        ZStack {
            content
                .id(activityID)
                .notchTransition(.swap)
        }
        .notchAnimation(value: activityID)
    }

    @ViewBuilder
    private var content: some View {
        Group {
            switch activityID {
            case AppCoordinator.ActivityKind.nowPlaying:
                TrackArtwork(image: coordinator.nowPlaying.artwork, version: coordinator.nowPlaying.artworkVersion)
            case AppCoordinator.ActivityKind.meeting:
                Image(systemName: "video.fill")
                    .foregroundStyle(coordinator.calendar.imminentMeeting.map(\.swiftUIColor) ?? .white)
            case AppCoordinator.ActivityKind.power:
                Image(systemName: coordinator.battery.state?.isPluggedIn == true ? "bolt.fill" : "powerplug")
                    .foregroundStyle(coordinator.battery.state?.isPluggedIn == true ? .green : .white)
            case AppCoordinator.ActivityKind.privacy:
                let camera = coordinator.privacy.isCameraActive
                if coordinator.isMicrophoneMuted {
                    Image(systemName: "mic.slash.fill").foregroundStyle(.red)
                } else {
                    Image(systemName: camera ? "video.fill" : "mic.fill")
                        .foregroundStyle(camera ? .green : .orange)
                }
            case AppCoordinator.ActivityKind.hud:
                WideWingLabel(symbol: coordinator.hud.symbolName, tint: .white, text: coordinator.hud.title)
            case AppCoordinator.ActivityKind.download:
                if let download = coordinator.downloads.active.first {
                    WideWingLabel(symbol: "arrow.down.circle.fill", tint: .blue, text: download.name)
                }
            case AppCoordinator.ActivityKind.downloadDone:
                WideWingLabel(symbol: "checkmark.circle.fill", tint: .green, text: String(localized: "İndirildi"))
            case AppCoordinator.ActivityKind.trackChange:
                if let info = coordinator.nowPlaying.info {
                    HStack(spacing: 6) {
                        TrackArtwork(image: coordinator.nowPlaying.artwork, version: coordinator.nowPlaying.artworkVersion)
                        // Uzun ad kayarak tamamı gösterilir; önizlemenin süresi buna göre uzar.
                        MarqueeText(text: info.title, size: 13, weight: .semibold)
                    }
                    .padding(.leading, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            case AppCoordinator.ActivityKind.audioOutput:
                if let device = coordinator.audioOutput.current {
                    WideWingLabel(symbol: AudioOutputMonitor.symbolName(for: device), tint: .white, text: device.name)
                }
            case AppCoordinator.ActivityKind.keepAwake:
                Image(systemName: "cup.and.saucer.fill").foregroundStyle(.orange)
            case AppCoordinator.ActivityKind.timer:
                // Saniyelik çizim yalnız zamanlayıcı çalışıp kanat ekrandayken.
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    ProgressRing(progress: coordinator.timer.progress(at: timeline.date),
                                 tint: coordinator.ui.pomodoroPhase?.tint ?? .orange)
                        .frame(width: 14, height: 14)
                }
            case AppCoordinator.ActivityKind.timerDone:
                if let phase = coordinator.ui.pomodoroPhase {
                    // Pomodoro'da biten değil başlayan evre söylenir.
                    WideWingLabel(symbol: phase.isBreak ? "cup.and.saucer.fill" : "leaf.fill", tint: phase.tint,
                                  text: phase.title)
                } else {
                    WideWingLabel(symbol: "timer", tint: .orange, text: String(localized: "Süre doldu"))
                }
            case AppCoordinator.ActivityKind.claudeUsage:
                WideWingLabel(symbol: "sparkles", tint: Color(red: 0.85, green: 0.47, blue: 0.34),
                              text: String(localized: "Claude oturumu"))
            case AppCoordinator.ActivityKind.batteryLow:
                WideWingLabel(symbol: "battery.25", tint: .red, text: String(localized: "Pil azaldı"))
            case AppCoordinator.ActivityKind.batteryFull:
                WideWingLabel(symbol: "battery.100.bolt", tint: .green, text: String(localized: "Tam şarj"))
            case AppCoordinator.ActivityKind.lockWidget:
                if let info = coordinator.nowPlaying.info, coordinator.settings.nowPlayingEnabled {
                    HStack(spacing: 8) {
                        TrackArtwork(image: coordinator.nowPlaying.artwork, version: coordinator.nowPlaying.artworkVersion)
                        MarqueeText(text: info.title, size: 13, weight: .semibold)
                    }
                    .padding(.leading, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if let state = coordinator.battery.state {
                    WideWingLabel(symbol: state.symbolName, tint: state.isCharging ? .green : (state.percent <= 20 ? .red : .white),
                                  text: NowFormat.percent(Double(state.percent)))
                }
            case AppCoordinator.ActivityKind.ci:
                if let run = coordinator.ci.activeRuns.first {
                    WideWingLabel(symbol: "hammer.fill", tint: .orange,
                                  text: run.workflow.isEmpty ? run.repositoryName : "\(run.repositoryName) · \(run.workflow)")
                }
            case AppCoordinator.ActivityKind.ciDone:
                if let run = coordinator.ui.lastFinishedRun {
                    WideWingLabel(symbol: CIStateIcon.symbol(for: run.state), tint: CIStateIcon.tint(for: run.state),
                                  text: run.workflow.isEmpty ? run.repositoryName : "\(run.repositoryName) · \(run.workflow)")
                }
            case AppCoordinator.ActivityKind.screenRecording:
                Image(systemName: "record.circle.fill")
                    .foregroundStyle(.purple)
                    .help("Ekran kaydediliyor ya da paylaşılıyor")
            case AppCoordinator.ActivityKind.microphone:
                let muted = coordinator.microphone.isMuted
                WideWingLabel(symbol: muted ? "mic.slash.fill" : "mic.fill", tint: muted ? .red : .white,
                              text: muted ? String(localized: "Mikrofon kapalı") : String(localized: "Mikrofon açık"))
            case AppCoordinator.ActivityKind.bluetooth:
                if let event = coordinator.ui.bluetoothEvent {
                    WideWingLabel(symbol: event.device.symbolName,
                                  tint: event.change == .disconnected ? .secondary : .white, text: event.device.shortName)
                }
            default:
                if let activity = coordinator.externalActivity(for: activityID) {
                    HStack(spacing: 6) {
                        Image(systemName: activity.symbolName).foregroundStyle(activity.tintColor)
                        // Kanat kapalı notch'ta sürekli görünür: uzun başlık bir kez kayar, döngü yok.
                        MarqueeText(text: activity.title, size: 13, weight: .semibold)
                    }
                    // Boşluk çerçeveden önce: kanat sabit genişlikte, boşluk onun içinde kalmalı.
                    .padding(.leading, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white)
    }
}
