import Integrations
import SwiftUI

/// Zamanlayıcı: hazır sürelerle başlat; çalışırken kalan süre, +1 dk ve iptal.
struct TimerTab: View {
    let timer: CountdownTimer

    private static let presets = [1, 5, 10, 15, 25, 45]

    var body: some View {
        if timer.isRunning {
            // Saniyelik çizim yalnız sekme açıkken; kapanınca TimelineView da durur.
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                HStack(spacing: 18) {
                    ProgressRing(progress: timer.progress(at: timeline.date), tint: .orange)
                        .frame(width: 44, height: 44)
                    Text(CountdownTimer.format(timer.remaining(at: timeline.date)))
                        .font(.system(size: 34, weight: .semibold).monospacedDigit())
                    Spacer(minLength: 8)
                    Button("+1 dk") { timer.add(seconds: 60) }
                        .controlSize(.small)
                    Button("İptal", role: .cancel) { timer.cancel() }
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            VStack(spacing: 12) {
                Text("Süre seçin")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(Self.presets, id: \.self) { minutes in
                        Button {
                            timer.start(seconds: TimeInterval(minutes * 60))
                        } label: {
                            Text("\(minutes) dk")
                                .font(.system(size: 12, weight: .semibold))
                                .frame(minWidth: 44, minHeight: 28)
                                .background(Capsule().fill(.white.opacity(0.12)))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
