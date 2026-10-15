import ActivityAPI
import SwiftUI

/// Dış etkinlikler: `notch` komutu, betikler ve Kestirmeler buraya yazar.
struct ActivitiesTab: View {
    let store: ExternalActivityStore

    var body: some View {
        if store.activities.isEmpty {
            EmptyStateView(symbol: "square.stack.3d.up", title: "Henüz dış etkinlik yok",
                           message: "Betikler, AI ajanları ve Kestirmeler buraya etkinlik gönderebilir.") {
                Text(verbatim: "notch push --id build --title Build --progress 40%")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
        } else {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(store.activities) { activity in
                        ActivityRow(activity: activity).notchCard()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct ActivityRow: View {
    let activity: ExternalActivity

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: activity.symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(activity.tintColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(activity.title)
                        .font(NotchDesign.bodyEmphasized)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    if let progress = activity.progress {
                        Text("%\(Int((progress * 100).rounded()))")
                            .font(NotchDesign.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                if let subtitle = activity.subtitle {
                    Text(subtitle)
                        .font(NotchDesign.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let progress = activity.progress {
                    // macOS doğrulusal ProgressView .tint'i yok sayıyor; renk için elle çizilir.
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(NotchDesign.track)
                            Capsule().fill(activity.tintColor).frame(width: proxy.size.width * progress)
                        }
                    }
                    .frame(height: 4)
                }
            }
        }
    }
}
