import Integrations
import SwiftUI

struct MediaTab: View {
    let nowPlaying: NowPlayingController
    let sourceDescription: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let info = nowPlaying.info {
                HStack(alignment: .center, spacing: 14) {
                    artwork
                    VStack(alignment: .leading, spacing: 3) {
                        Text(info.title)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Text(subtitle(for: info))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        ProgressRow(info: info, accent: accent, canSeek: nowPlaying.canSeek) { seconds in
                            nowPlaying.seek(to: seconds)
                        }
                        .padding(.top, 4)
                    }
                    Spacer(minLength: 6)
                    controls(isPlaying: info.isPlaying)
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "music.note")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                    (nowPlaying.source == .checking ? Text("Medya kaynağı denetleniyor…") : Text("Şu an bir şey çalmıyor"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 64)
            }
            Spacer(minLength: 0)
            Text(sourceDescription)
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    private var accent: Color {
        nowPlaying.accentColor.map(Color.init(nsColor:)) ?? .white
    }

    private var artwork: some View {
        Group {
            if let image = nowPlaying.artwork {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.white.opacity(0.08)
                    Image(systemName: "music.note").font(.system(size: 22)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func subtitle(for info: NowPlayingInfo) -> String {
        let artist = info.artist ?? ""
        let app = info.bundleIdentifier.flatMap(Self.appName(for:)) ?? ""
        return [artist, app].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func controls(isPlaying: Bool) -> some View {
        HStack(spacing: 6) {
            controlButton("backward.fill", size: 15, help: "Önceki") { nowPlaying.previousTrack() }
            controlButton(isPlaying ? "pause.fill" : "play.fill", size: 22,
                          help: isPlaying ? LocalizedStringKey("Duraklat") : LocalizedStringKey("Oynat")) {
                nowPlaying.togglePlayPause()
            }
            controlButton("forward.fill", size: 15, help: "Sonraki") { nowPlaying.nextTrack() }
        }
    }

    private func controlButton(_ symbol: String, size: CGFloat, help: LocalizedStringKey,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    static func appName(for bundleIdentifier: String) -> String? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
            .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
    }
}

/// İlerleme çubuğu. Yalnız çalarken ve notch açıkken saniyede bir çizilir; duraklatınca durur.
private struct ProgressRow: View {
    let info: NowPlayingInfo
    let accent: Color
    let canSeek: Bool
    let seek: (TimeInterval) -> Void

    var body: some View {
        if let duration = info.duration, duration > 0 {
            TimelineView(.animation(minimumInterval: 1, paused: !info.isPlaying)) { timeline in
                let elapsed = info.elapsed(at: timeline.date) ?? 0
                HStack(spacing: 6) {
                    Text(Self.format(elapsed))
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.15))
                            Capsule().fill(accent)
                                .frame(width: proxy.size.width * min(1, elapsed / duration))
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            guard canSeek, proxy.size.width > 0 else { return }
                            seek(duration * min(max(location.x / proxy.size.width, 0), 1))
                        }
                    }
                    .frame(height: 4)
                    Text("-" + Self.format(max(0, duration - elapsed)))
                }
                .font(.system(size: 9.5).monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
