import ActivityAPI
import SwiftUI

/// Dış etkinlikler: `notch` komutu, betikler ve Kestirmeler buraya yazar.
struct ActivitiesTab: View {
    let store: ExternalActivityStore

    var body: some View {
        if store.activities.isEmpty {
            VStack(spacing: 6) {
                Text("Henüz dış etkinlik yok")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("notch push --id build --title Derleme --progress 40%")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(store.activities) { activity in
                        ActivityRow(activity: activity)
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
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    if let progress = activity.progress {
                        Text("%\(Int((progress * 100).rounded()))")
                            .font(.system(size: 10.5).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                if let subtitle = activity.subtitle {
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let progress = activity.progress {
                    // macOS doğrulusal ProgressView .tint'i yok sayıyor; renk için elle çizilir.
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.15))
                            Capsule().fill(activity.tintColor).frame(width: proxy.size.width * progress)
                        }
                    }
                    .frame(height: 4)
                }
            }
        }
    }
}
