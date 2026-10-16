import ActivityAPI
import ActivityEngine
import Integrations
import NotchShell
import SwiftUI

/// Bir ekranın notch içeriği: kabuk (şekil, animasyon, hover) NotchShell'den, içerik buradan.
struct NotchRootView: View {
    let model: NotchSurfaceModel
    let coordinator: AppCoordinator

    var body: some View {
        NotchSurfaceView(model: model) {
            CompactLeadingView(coordinator: coordinator, activityID: coordinator.displayedActivityID)
        } compactTrailing: {
            CompactTrailingView(coordinator: coordinator, activityID: coordinator.displayedActivityID)
        } expanded: { context in
            // Kilitte panel açılmıyor (2026-10-15 günlüğü: kilit süresince hover yok); yine de
            // açılırsa raf, takvim ve etkinlikler kilit ekranına düşmesin.
            if !coordinator.lockScreen.isLocked {
                ExpandedView(context: context, model: model, coordinator: coordinator)
            }
        }
        .environment(\.pausesContinuousMotion, coordinator.isMotionPaused)
    }
}

/// Kilit ekranındaki notch: yalnız kompakt, yalnız kişisel içerik taşımayan etkinlikler.
/// Panel olay almadığı için açılmaz; açık görünüm boş.
struct LockScreenRootView: View {
    let model: NotchSurfaceModel
    let coordinator: AppCoordinator

    var body: some View {
        NotchSurfaceView(model: model) {
            CompactLeadingView(coordinator: coordinator, activityID: coordinator.lockScreenActivityID)
        } compactTrailing: {
            CompactTrailingView(coordinator: coordinator, activityID: coordinator.lockScreenActivityID)
        } expanded: { _ in
            EmptyView()
        }
        .environment(\.pausesContinuousMotion, coordinator.isMotionPaused)
    }
}

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

extension CalendarMonitor.Event {
    var swiftUIColor: Color {
        Color(.sRGB, red: color[safe: 0] ?? 0.5, green: color[safe: 1] ?? 0.5, blue: color[safe: 2] ?? 0.5)
    }

    func compactCountdown(at now: Date) -> String {
        guard start > now else { return String(localized: "şimdi") }
        let minutes = Int((start.timeIntervalSince(now) / 60).rounded(.up))
        return String(localized: "\(minutes) dk")
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

struct ProgressRing: View {
    let progress: Double
    let tint: Color

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.2), lineWidth: 2.5)
            Circle().trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .notchAnimation(.linear(duration: 0.3), value: progress)
    }
}

extension ExternalActivity {
    /// Geçersiz ya da bu sistemde olmayan sembol adı yerine genel simge.
    var symbolName: String {
        guard let symbol, NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil else {
            return "app.badge"
        }
        return symbol
    }

    var tintColor: Color {
        guard let tint, tint.count == 7, let value = UInt32(tint.dropFirst(), radix: 16) else { return .white }
        return Color(.sRGB, red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                     blue: Double(value & 0xFF) / 255)
    }
}

/// Geniş kanadın sol tarafı: sembol ve kısa metin, görünen kenardan 12 pt içeride.
/// Kompakt kanatta küçük kapak; yoksa nota simgesi. Kapak değişince çapraz geçiş.
struct TrackArtwork: View {
    let image: NSImage?
    let version: Int

    var body: some View {
        ZStack {
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                } else {
                    Image(systemName: "music.note")
                }
            }
            .id(version)
            .notchTransition(.fade)
        }
        .frame(width: 20, height: 20)
        .notchAnimation(value: version)
    }
}

/// Geniş kanatta simge + metin. Metin sığmazsa bir kez kayarak tamamı gösterilir (kesilmez);
/// kısa bildirimin süresi `AppCoordinator.readableFlashDuration` ile buna göre uzar.
struct WideWingLabel: View {
    let symbol: String
    let tint: Color
    let text: String

    /// Kanatta metne kalan genişlik: kanat − baş boşluk (12) − simge (~16) − aralık (6).
    static var textWidth: CGFloat { AppCoordinator.wideWingWidth - 34 }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(tint)
            MarqueeText(text: text, size: 13, weight: .semibold)
        }
        .padding(.leading, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LevelBar: View {
    let level: Double
    var tint: Color = .white

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2))
                Capsule().fill(tint).frame(width: proxy.size.width * min(max(level, 0), 1))
            }
        }
        // Düzey değişince (ses, işlemci, bellek, Claude) çubuk sıçramaz, kayar.
        .notchAnimation(value: level)
    }
}

extension HUDController {
    var symbolName: String {
        switch kind {
        case .brightness:
            return "sun.max.fill"
        case .volume:
            if isMuted || level == 0 { return "speaker.slash.fill" }
            if level < 0.34 { return "speaker.wave.1.fill" }
            if level < 0.67 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        }
    }

    var title: String {
        switch kind {
        case .brightness: String(localized: "Parlaklık")
        case .volume: isMuted ? String(localized: "Sessiz") : String(localized: "Ses")
        }
    }
}

/// Bluetooth kısa bildiriminin sağ kanadı: bağlanınca pil, azalınca kırmızı pil, ayrılınca "Ayrıldı".
private struct BluetoothEventDetail: View {
    let event: BluetoothEvent

    var body: some View {
        switch event.change {
        case .disconnected:
            Text("Ayrıldı").foregroundStyle(.secondary)
        case let .lowBattery(level):
            BatteryLevelLabel(level: level, tint: .red)
        case .connected:
            if let level = event.device.lowest {
                BatteryLevelLabel(level: level, tint: level <= 20 ? .red : .secondary)
            }
        }
    }
}

/// Aygıt pili: simge ve yerel yüzde ("%80" / "80%").
struct BatteryLevelLabel: View {
    let level: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(verbatim: NowFormat.percent(Double(level))).monospacedDigit()
            Image(systemName: BluetoothMonitor.Device.batterySymbol(for: level))
        }
        .foregroundStyle(tint)
    }
}

extension BluetoothMonitor.Device {
    var symbolName: String {
        switch kind {
        case .headphones:
            if name.localizedCaseInsensitiveContains("AirPods Pro") { "airpodspro" }
            else if name.localizedCaseInsensitiveContains("AirPods Max") { "airpodsmax" }
            else if name.localizedCaseInsensitiveContains("AirPods") { "airpods" }
            else { "headphones" }
        case .keyboard: "keyboard"
        case .mouse: "magicmouse"
        case .trackpad: "rectangle.and.hand.point.up.left"
        case .speaker: "hifispeaker"
        case .gamepad: "gamecontroller"
        case .other: "wave.3.right"
        }
    }

    /// Kulaklıkta sol/sağ/kutu ayrı; diğerlerinde tek pil.
    var batteryHelp: String {
        var parts: [String] = []
        if let main { parts.append(NowFormat.percent(Double(main))) }
        if let left { parts.append(String(localized: "sol \(NowFormat.percent(Double(left)))")) }
        if let right { parts.append(String(localized: "sağ \(NowFormat.percent(Double(right)))")) }
        if let caseLevel { parts.append(String(localized: "kutu \(NowFormat.percent(Double(caseLevel)))")) }
        return ([name] + parts).joined(separator: " · ")
    }

    static func batterySymbol(for level: Int) -> String {
        switch level {
        case ..<13: "battery.0percent"
        case ..<38: "battery.25percent"
        case ..<63: "battery.50percent"
        case ..<88: "battery.75percent"
        default: "battery.100percent"
        }
    }
}

/// Kilit şeridinin sağı: müzik çalıyorsa pil; müzik yoksa (solda pil) kalan ya da dolma süresi.
private struct LockWidgetTrailing: View {
    let coordinator: AppCoordinator

    var body: some View {
        if let state = coordinator.battery.state {
            if coordinator.nowPlaying.info != nil, coordinator.settings.nowPlayingEnabled {
                HStack(spacing: 4) {
                    Text(verbatim: NowFormat.percent(Double(state.percent))).monospacedDigit()
                    Image(systemName: state.symbolName)
                        .foregroundStyle(state.isCharging ? .green : (state.percent <= 20 ? .red : .secondary))
                }
                .foregroundStyle(.secondary)
            } else if let text = Self.remaining(state) {
                Text(text).monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }

    /// "1 sa 20 dk kaldı" / "dolmasına 35 dk"; sistem hesaplamıyorsa nil.
    static func remaining(_ state: BatteryMonitor.State) -> String? {
        let minutes = state.isCharging ? state.minutesToFull : (state.isPluggedIn ? nil : state.minutesToEmpty)
        guard let minutes, minutes > 0 else { return state.isPluggedIn && !state.isCharging ? String(localized: "Şarj tamam") : nil }
        let duration = minutes >= 60 ? String(localized: "\(minutes / 60) sa \(minutes % 60) dk") : String(localized: "\(minutes) dk")
        return state.isCharging ? String(localized: "dolmasına \(duration)") : String(localized: "\(duration) kaldı")
    }
}
