import Integrations
import SwiftUI

struct MediaTab: View {
    let nowPlaying: NowPlayingController
    let sourceDescription: String

    var body: some View {
        if let info = nowPlaying.info {
            HStack(alignment: .center, spacing: 14) {
                artwork
                VStack(alignment: .leading, spacing: 3) {
                    Text(info.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text(subtitle(for: info))
                        .font(NotchDesign.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    ProgressRow(info: info, accent: accent, canSeek: nowPlaying.canSeek) { seconds in
                        nowPlaying.seek(to: seconds)
                    }
                    .padding(.top, 8)
                }
                .help(sourceDescription)
                Spacer(minLength: 8)
                controls(isPlaying: info.isPlaying)
            }
            .frame(maxHeight: .infinity)
        } else {
            EmptyStateView(symbol: "music.note",
                           title: nowPlaying.source == .checking ? "Medya kaynağı denetleniyor…" : "Şu an bir şey çalmıyor",
                           message: LocalizedStringKey(sourceDescription))
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
                    NotchDesign.cardFill
                    Image(systemName: "music.note").font(.system(size: 24)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 84, height: 84)
        .clipShape(RoundedRectangle(cornerRadius: NotchDesign.cardRadius, style: .continuous))
    }

    private func subtitle(for info: NowPlayingInfo) -> String {
        let artist = info.artist ?? ""
        let app = info.bundleIdentifier.flatMap(Self.appName(for:)) ?? ""
        return [artist, app].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func controls(isPlaying: Bool) -> some View {
        HStack(spacing: 4) {
            controlButton("backward.fill", size: 15, frame: 34, help: "Önceki") { nowPlaying.previousTrack() }
            controlButton(isPlaying ? "pause.fill" : "play.fill", size: 22, frame: 42,
                          help: isPlaying ? LocalizedStringKey("Duraklat") : LocalizedStringKey("Oynat")) {
                nowPlaying.togglePlayPause()
            }
            controlButton("forward.fill", size: 15, frame: 34, help: "Sonraki") { nowPlaying.nextTrack() }
        }
    }

    private func controlButton(_ symbol: String, size: CGFloat, frame: CGFloat, help: LocalizedStringKey,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size))
        }
        .buttonStyle(IconButtonStyle(size: frame))
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
                            Capsule().fill(NotchDesign.track)
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
