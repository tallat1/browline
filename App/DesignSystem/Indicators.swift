import ActivityAPI
import ActivityEngine
import Integrations
import NotchShell
import SwiftUI

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
