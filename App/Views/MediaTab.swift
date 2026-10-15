import AppKit
import Integrations
import NotchShell
import SwiftUI

/// Medya: kapak (tıklayınca oynatıcıyı açar), başlık, sürüklenebilir ilerleme; altında denetimler
/// (±15 sn, önceki/oynat/sonraki, oynatıcı bildirirse karıştır/tekrar) ve ses + çıkış seçici.
/// Birden çok oynatıcı varken sağ üstte oturum seçici. Kaydırıcı ya da menü kullanılırken notch
/// sabitlenir; imleç dışarı kayınca kapanmaz.
struct MediaTab: View {
    let nowPlaying: NowPlayingController
    let volume: VolumeController
    let model: NotchSurfaceModel
    let sourceDescription: String

    var body: some View {
        // Çalan yokken ↔ çalarken: boş durum ile oynatıcı arası çapraz geçiş (şarkı geçişinde
        // denetleyici bilgiyi 1,5 sn tuttuğu için burada boşalma görülmez).
        ZStack {
            player.notchTransition(.swap)
        }
        .notchAnimation(value: nowPlaying.info == nil)
        // Elle seçilen ama çalmayan oturum bırakılır: kapalı notch çalanı göstersin.
        .onDisappear { nowPlaying.releaseSelection() }
    }

    @ViewBuilder
    private var player: some View {
        if let info = nowPlaying.info {
            VStack(spacing: 10) {
                HStack(alignment: .center, spacing: 14) {
                    artwork(bundleIdentifier: info.bundleIdentifier)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .top, spacing: 8) {
                            // Şarkı değişince başlık ve sanatçı çapraz geçişle; uzun başlık kayar.
                            VStack(alignment: .leading, spacing: 3) {
                                MarqueeText(text: info.title, size: 14, weight: .semibold, loops: true)
                                Text(subtitle(for: info))
                                    .font(NotchDesign.body)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .id(info.title)
                            .notchTransition(.swap)
                            if nowPlaying.sessions.count > 1 {
                                SessionSwitcher(sessions: nowPlaying.sessions, focusedID: nowPlaying.focusedSessionID) {
                                    nowPlaying.selectSession($0)
                                }
                                .notchTransition(.fade)
                            }
                        }
                        .notchAnimation(value: nowPlaying.sessions.count > 1)
                        Spacer(minLength: 4)
                        ScrubBar(info: info, accent: accent, canSeek: nowPlaying.canSeek,
                                 onBegin: { model.tapped() }) { seconds in
                            nowPlaying.seek(to: seconds)
                        }
                    }
                    .frame(height: 84)
                    .help(sourceDescription)
                }
                HStack(spacing: 2) {
                    controls(info: info)
                    Spacer(minLength: 8)
                    VolumeControl(volume: volume) { model.tapped() }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .notchAnimation(value: info.title)
        } else {
            EmptyStateView(symbol: "music.note",
                           title: nowPlaying.source == .checking ? "Medya kaynağı denetleniyor…" : "Şu an bir şey çalmıyor",
                           message: LocalizedStringKey(sourceDescription))
        }
    }

    private var accent: Color {
        nowPlaying.accentColor.map(Color.init(nsColor:)) ?? .white
    }

    /// Kapağa tıklayınca çalan uygulama öne gelir (boring.notch'taki gibi).
    private func artwork(bundleIdentifier: String?) -> some View {
        Button {
            guard let bundleIdentifier,
                  let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return }
            AppLog.coordinator.notice("medya: oynatıcı açılıyor (\(bundleIdentifier, privacy: .public))")
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } label: {
            ZStack {
                Group {
                    if let image = nowPlaying.artwork {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        ZStack {
                            NotchDesign.cardFill
                            Image(systemName: "music.note").font(.system(size: 24)).foregroundStyle(.secondary)
                        }
                    }
                }
                .id(nowPlaying.artworkVersion)
                .notchTransition(.fade)
            }
            .notchAnimation(value: nowPlaying.artworkVersion)
            .frame(width: 84, height: 84)
            .clipShape(RoundedRectangle(cornerRadius: NotchDesign.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(bundleIdentifier.flatMap(Self.appName(for:)).map { String(localized: "\($0) uygulamasını aç") } ?? "")
    }

    private func subtitle(for info: NowPlayingInfo) -> String {
        let artist = info.artist ?? ""
        let app = info.bundleIdentifier.flatMap(Self.appName(for:)) ?? ""
        return [artist, app].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    @ViewBuilder
    private func controls(info: NowPlayingInfo) -> some View {
        if nowPlaying.supportsShuffleAndRepeat {
            toggle("shuffle", isOn: info.shuffleMode != 1, help: "Karıştır") { nowPlaying.cycleShuffle() }
        }
        if nowPlaying.canSeek {
            control("gobackward.15", size: 15, frame: 32, help: "15 sn geri") {
                AppLog.coordinator.notice("medya: 15 sn geri")
                nowPlaying.skip(by: -15)
            }
        }
        control("backward.fill", size: 15, frame: 34, help: "Önceki", enabled: nowPlaying.canSkipTracks) {
            nowPlaying.previousTrack()
        }
        control(info.isPlaying ? "pause.fill" : "play.fill", size: 22, frame: 42,
                help: info.isPlaying ? LocalizedStringKey("Duraklat") : LocalizedStringKey("Oynat")) {
            nowPlaying.togglePlayPause()
        }
        control("forward.fill", size: 15, frame: 34, help: "Sonraki", enabled: nowPlaying.canSkipTracks) {
            nowPlaying.nextTrack()
        }
        if nowPlaying.canSeek {
            control("goforward.15", size: 15, frame: 32, help: "15 sn ileri") {
                AppLog.coordinator.notice("medya: 15 sn ileri")
                nowPlaying.skip(by: 15)
            }
        }
        if nowPlaying.supportsShuffleAndRepeat {
            toggle(info.repeatMode == 2 ? "repeat.1" : "repeat", isOn: info.repeatMode != 1, help: "Tekrarla") {
                nowPlaying.cycleRepeat()
            }
        }
    }

    private func control(_ symbol: String, size: CGFloat, frame: CGFloat, help: LocalizedStringKey,
                         enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size))
        }
        .buttonStyle(IconButtonStyle(size: frame))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .help(enabled ? help : "Bu oynatıcı parça atlamayı desteklemiyor")
    }

    private func toggle(_ symbol: String, isOn: Bool, help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isOn ? accent : .secondary)
        }
        .buttonStyle(IconButtonStyle(size: 30))
        .help(help)
    }

    static func appName(for bundleIdentifier: String) -> String? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
            .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
    }
}

/// Birden çok oynatıcı varken (ör. Chrome'da video, Spotify'da şarkı): uygulama simgeleri. Basınca
/// o oturum gösterilir ve denetimler ona gider; çalan oturumun simgesinde nokta.
private struct SessionSwitcher: View {
    let sessions: [MediaSession]
    let focusedID: String?
    let select: (String) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(sessions) { session in
                Button {
                    AppLog.coordinator.notice("medya: oturum seçici (\(session.id, privacy: .public))")
                    select(session.id)
                } label: {
                    SessionIcon(session: session, isSelected: session.id == focusedID)
                }
                .buttonStyle(.plain)
                .help(Self.help(for: session))
                .notchTransition(.listItem)
            }
        }
        .padding(2)
        .background(Capsule().fill(NotchDesign.cardFill))
        .notchAnimation(value: sessions.map(\.id))
        .notchAnimation(NotchMotion.hover, value: focusedID)
    }

    static func help(for session: MediaSession) -> String {
        let app = session.appBundleIdentifier.flatMap(MediaTab.appName(for:)) ?? session.displayName ?? ""
        let title = session.info.title
        return session.info.isPlaying ? String(localized: "\(app) — \(title)")
            : String(localized: "\(app) — \(title) (duraklatıldı)")
    }
}

private struct SessionIcon: View {
    let session: MediaSession
    let isSelected: Bool
    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AppIcon(bundleIdentifier: session.appBundleIdentifier)
                .frame(width: 16, height: 16)
                .frame(width: 24, height: 24)
            if session.info.isPlaying {
                Circle()
                    .fill(.white)
                    .frame(width: 6, height: 6)
                    .overlay(Circle().stroke(.black, lineWidth: 1.5))
                    .offset(x: -2, y: -2)
                    .notchTransition(.fade)
            }
        }
        .frame(width: 24, height: 24)
        .background(Circle().fill(isSelected ? NotchDesign.selectionFill
                                  : (isHovering ? NotchDesign.cardHoverFill : .clear)))
        .opacity(isSelected || isHovering ? 1 : 0.55)
        .contentShape(Circle())
        .onHover { isHovering = $0 }
        .notchAnimation(NotchMotion.hover, value: isHovering)
        .notchAnimation(value: session.info.isPlaying)
    }
}

/// Uygulama simgesi; bulunamazsa müzik notası. Önbellekte: yeniden çizimde disk okunmaz.
private struct AppIcon: View {
    let bundleIdentifier: String?

    var body: some View {
        if let image = Self.icon(for: bundleIdentifier) {
            Image(nsImage: image).resizable().interpolation(.high)
        } else {
            Image(systemName: "music.note")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    @MainActor private static var cache: [String: NSImage] = [:]

    @MainActor private static func icon(for bundleIdentifier: String?) -> NSImage? {
        guard let bundleIdentifier else { return nil }
        if let cached = cache[bundleIdentifier] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleIdentifier] = image
        return image
    }
}

/// İlerleme: tıkla ya da sürükle. Tutma alanı çizgiden yüksek (18 pt); üzerine gelince ya da
/// sürüklerken kalınlaşır ve tutamaç çıkar, süreler sürüklenen konumu gösterir. Yalnız çalarken
/// ve notch açıkken saniyede bir çizilir.
private struct ScrubBar: View {
    let info: NowPlayingInfo
    let accent: Color
    let canSeek: Bool
    let onBegin: () -> Void
    let seek: (TimeInterval) -> Void
    @State private var dragFraction: Double?
    @State private var isHovering = false

    var body: some View {
        if let duration = info.duration, duration > 0 {
            TimelineView(.animation(minimumInterval: 1, paused: !info.isPlaying || dragFraction != nil)) { timeline in
                let elapsed = dragFraction.map { $0 * duration } ?? (info.elapsed(at: timeline.date) ?? 0)
                let active = canSeek && (isHovering || dragFraction != nil)
                HStack(spacing: 8) {
                    Text(Self.format(elapsed))
                    GeometryReader { proxy in
                        let width = max(proxy.size.width, 1)
                        let fraction = min(1, max(0, elapsed / duration))
                        ZStack(alignment: .leading) {
                            Capsule().fill(NotchDesign.track).frame(height: active ? 6 : 4)
                            Capsule().fill(accent).frame(width: width * fraction, height: active ? 6 : 4)
                            if active {
                                Circle().fill(.white).frame(width: 12, height: 12)
                                    .offset(x: width * fraction - 6)
                            }
                        }
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard canSeek else { return }
                                if dragFraction == nil {
                                    AppLog.coordinator.notice("medya: ilerleme sürükleniyor")
                                    onBegin()
                                }
                                dragFraction = min(1, max(0, value.location.x / width))
                            }
                            .onEnded { value in
                                guard canSeek else { return }
                                seek(min(1, max(0, value.location.x / width)) * duration)
                                dragFraction = nil
                            })
                        .onHover { isHovering = $0 }
                        .notchAnimation(NotchMotion.hover, value: active)
                    }
                    .frame(height: 18)
                    Text("-" + Self.format(max(0, duration - elapsed)))
                }
                .font(NotchDesign.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Ses: sessize al düğmesi, kaydırıcı ve çıkış cihazı menüsü. Dinleyiciler yalnız görünürken.
private struct VolumeControl: View {
    let volume: VolumeController
    let onInteract: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button { volume.toggleMute() } label: {
                Image(systemName: speakerSymbol).font(.system(size: 12, weight: .semibold)).frame(width: 18)
            }
            .buttonStyle(IconButtonStyle(size: 28))
            .help(volume.isMuted ? "Sesi aç" : "Sessize al")
            VolumeSlider(value: volume.isMuted ? 0 : volume.volume, isEnabled: volume.isSettable,
                         onBegin: onInteract) { volume.setVolume($0) }
                .frame(width: 110, height: 18)
            Button {
                onInteract()
                OutputMenu.show(volume: volume)
            } label: {
                Image(systemName: "airplayaudio").font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(IconButtonStyle(size: 28))
            .help("Ses çıkışı")
        }
        .foregroundStyle(.secondary)
        .onAppear { volume.start() }
        .onDisappear { volume.stop() }
    }

    private var speakerSymbol: String {
        if volume.isMuted || volume.volume == 0 { return "speaker.slash.fill" }
        return volume.volume < 0.34 ? "speaker.wave.1.fill" : (volume.volume < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill")
    }
}

/// Notch'a uyan ince kaydırıcı (macOS Slider koyu zeminde ve dar alanda zayıf görünüyor).
private struct VolumeSlider: View {
    let value: Double
    let isEnabled: Bool
    let onBegin: () -> Void
    let onChange: (Double) -> Void
    @State private var isDragging = false
    @State private var isHovering = false

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let active = isEnabled && (isHovering || isDragging)
            ZStack(alignment: .leading) {
                Capsule().fill(NotchDesign.track).frame(height: active ? 6 : 4)
                Capsule().fill(Color.white.opacity(isEnabled ? 0.9 : 0.3))
                    .frame(width: width * value, height: active ? 6 : 4)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    guard isEnabled else { return }
                    if !isDragging {
                        isDragging = true
                        AppLog.coordinator.notice("medya: ses kaydırıcısı sürükleniyor")
                        onBegin()
                    }
                    onChange(min(1, max(0, drag.location.x / width)))
                }
                .onEnded { _ in isDragging = false })
            .onHover { isHovering = $0 }
            .notchAnimation(NotchMotion.hover, value: active)
        }
        .help(isEnabled ? "%\(Int((value * 100).rounded()))" : String(localized: "Bu çıkışın sesi ayarlanamıyor"))
    }
}

/// Çıkış cihazı menüsü; imlecin olduğu yerde açılır. Denetim Merkezi › Ses ile aynı liste
/// (AirPlay hedefleri bağlanınca görünür).
@MainActor
private enum OutputMenu {
    static func show(volume: VolumeController) {
        AppLog.coordinator.notice("medya: çıkış menüsü açıldı (\(volume.devices.count) cihaz)")
        let menu = NSMenu()
        let header = NSMenuItem(title: String(localized: "Ses çıkışı"), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for device in volume.devices {
            let item = NSMenuItem(title: device.name, action: #selector(MenuTarget.run), keyEquivalent: "")
            let target = MenuTarget { volume.selectOutput(device) }
            item.target = target
            item.representedObject = target
            item.state = device.id == volume.currentDeviceID ? .on : .off
            item.image = NSImage(systemSymbolName: AudioOutputMonitor.symbolName(
                for: .init(id: device.id, name: device.name, transport: device.transport)), accessibilityDescription: nil)
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    final class MenuTarget: NSObject {
        let handler: () -> Void
        init(_ handler: @escaping () -> Void) { self.handler = handler }
        @objc func run() { handler() }
    }
}
