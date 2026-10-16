import ActivityAPI
import ActivityEngine
import Integrations
import NotchShell
import SwiftUI

/// Çentiğin sağındaki kanat: durum (dalga formu, kalan dakika, şarj yüzdesi).
struct CompactTrailingView: View {
    let coordinator: AppCoordinator
    let activityID: ActivityID?

    static func ciResultTitle(_ state: CIMonitor.Run.State) -> LocalizedStringKey {
        switch state {
        case .success: "Başarılı"
        case .failure: "Başarısız"
        case .active, .other: "Bitti"
        }
    }

    var body: some View {
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
                // Çalarken hafifçe oynayan çubuklar; ayar kapalıysa ya da azaltılmış harekette durağan.
                EqualizerBars(isPlaying: coordinator.nowPlaying.info?.isPlaying == true,
                              tint: coordinator.nowPlaying.accentColor.map(Color.init(nsColor:)) ?? .white,
                              isEnabled: coordinator.settings.animatedEqualizer,
                              spectrum: coordinator.settings.reactiveEqualizer ? coordinator.spectrum : nil)
            case AppCoordinator.ActivityKind.meeting:
                if let event = coordinator.calendar.imminentMeeting {
                    // Dakikada bir güncellenir; yalnız toplantı yaklaşırken görünür.
                    TimelineView(.everyMinute) { timeline in
                        Text(event.compactCountdown(at: timeline.currentDate))
                    }
                }
            case AppCoordinator.ActivityKind.power:
                if let state = coordinator.battery.state {
                    Text("%\(state.percent)").monospacedDigit()
                }
            case AppCoordinator.ActivityKind.privacy:
                if coordinator.isMicrophoneMuted {
                    // Sol kanatta kırmızı mikrofon; sağda kamera açıksa yeşil, değilse kırmızı nokta.
                    Circle().fill(coordinator.privacy.isCameraActive ? .green : .red).frame(width: 7, height: 7)
                } else if coordinator.privacy.isCameraActive && coordinator.privacy.isMicrophoneActive {
                    Image(systemName: "mic.fill").foregroundStyle(.orange)
                } else {
                    Circle().fill(coordinator.privacy.isCameraActive ? .green : .orange).frame(width: 7, height: 7)
                }
            case AppCoordinator.ActivityKind.hud:
                HStack(spacing: 8) {
                    LevelBar(level: coordinator.hud.isMuted ? 0 : coordinator.hud.level)
                        .frame(width: 64, height: 5)
                    Text("%\(Int((coordinator.hud.level * 100).rounded()))")
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .notchAnimation(value: coordinator.hud.level)
                        .foregroundStyle(coordinator.hud.isMuted ? .secondary : .primary)
                }
                .padding(.trailing, 12)
                .frame(maxWidth: .infinity, alignment: .trailing)
            case AppCoordinator.ActivityKind.download:
                if let download = coordinator.downloads.active.first {
                    HStack(spacing: 6) {
                        if let fraction = download.fraction {
                            Text("%\(Int((fraction * 100).rounded()))").monospacedDigit()
                            ProgressRing(progress: fraction, tint: .blue).frame(width: 14, height: 14)
                        } else {
                            Text(ByteCountFormatter.string(fromByteCount: download.bytes, countStyle: .file))
                                .monospacedDigit()
                        }
                    }
                    .padding(.trailing, 12)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            case AppCoordinator.ActivityKind.trackChange:
                if let artist = coordinator.nowPlaying.info?.artist {
                    Text(artist)
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 12)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            case AppCoordinator.ActivityKind.audioOutput:
                if let percent = AudioOutputMonitor.volumePercent() {
                    Text("%\(percent)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 12)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            case AppCoordinator.ActivityKind.keepAwake:
                if let endsAt = coordinator.keepAwake.endsAt {
                    TimelineView(.everyMinute) { timeline in
                        let minutes = Int((max(0, endsAt.timeIntervalSince(timeline.currentDate)) / 60).rounded(.up))
                        Text("\(minutes) dk").monospacedDigit()
                    }
                }
            case AppCoordinator.ActivityKind.timer:
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    Text(CountdownTimer.format(coordinator.timer.remaining(at: timeline.date))).monospacedDigit()
                }
            case AppCoordinator.ActivityKind.timerDone:
                Text(CountdownTimer.format(coordinator.timer.duration))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 12)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            case AppCoordinator.ActivityKind.claudeUsage:
                if let percent = coordinator.claudeUsage.usage?.fiveHour?.usedPercentage {
                    Text(verbatim: "%\(Int(percent.rounded()))")
                        .monospacedDigit()
                        .foregroundStyle(percent >= 90 ? .red : .orange)
                        .padding(.trailing, 12)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            case AppCoordinator.ActivityKind.batteryLow, AppCoordinator.ActivityKind.batteryFull:
                if let state = coordinator.battery.state {
                    Text("%\(state.percent)")
                        .monospacedDigit()
                        .foregroundStyle(activityID == AppCoordinator.ActivityKind.batteryLow ? .red : .secondary)
                        .padding(.trailing, 12)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            case AppCoordinator.ActivityKind.lockWidget:
                LockWidgetTrailing(coordinator: coordinator)
                    .padding(.trailing, 12)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            case AppCoordinator.ActivityKind.ci:
                // İlk süren çalışmanın süresi; birden çoksa sayısı.
                if let run = coordinator.ci.activeRuns.first {
                    HStack(spacing: 6) {
                        if coordinator.ci.activeRuns.count > 1 {
                            Text(verbatim: "+\(coordinator.ci.activeRuns.count - 1)").foregroundStyle(.secondary)
                        }
                        TimelineView(.periodic(from: .now, by: 1)) { timeline in
                            Text(CountdownTimer.format(max(0, timeline.date.timeIntervalSince(run.createdAt))))
                                .monospacedDigit()
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.trailing, 12)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            case AppCoordinator.ActivityKind.ciDone:
                if let run = coordinator.ui.lastFinishedRun {
                    Text(Self.ciResultTitle(run.state))
                        .foregroundStyle(CIStateIcon.tint(for: run.state))
                        .padding(.trailing, 12)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            case AppCoordinator.ActivityKind.screenRecording:
                // Kaydın süresi; saniyelik çizim yalnız kayıt sürerken ve kanat ekrandayken.
                if let startedAt = coordinator.screenRecording.startedAt {
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        Text(CountdownTimer.format(max(0, timeline.date.timeIntervalSince(startedAt))))
                            .monospacedDigit()
                            .foregroundStyle(.purple)
                    }
                }
            case AppCoordinator.ActivityKind.microphone:
                // Mikrofonu kullanan uygulama (görüşme), yoksa boş.
                if let app = coordinator.microphone.inputApps.first {
                    Text(verbatim: app.name)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.trailing, 12)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            case AppCoordinator.ActivityKind.bluetooth:
                if let event = coordinator.ui.bluetoothEvent {
                    BluetoothEventDetail(event: event)
                        .padding(.trailing, 12)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            case AppCoordinator.ActivityKind.downloadDone:
                Text(coordinator.ui.lastFinishedDownload)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 12)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            default:
                if let activity = coordinator.externalActivity(for: activityID) {
                    HStack(spacing: 6) {
                        if let progress = activity.progress {
                            Text("%\(Int((progress * 100).rounded()))").monospacedDigit()
                            ProgressRing(progress: progress, tint: activity.tintColor)
                                .frame(width: 14, height: 14)
                        } else if let subtitle = activity.subtitle {
                            Text(subtitle).lineLimit(1).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.trailing, 12)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}
