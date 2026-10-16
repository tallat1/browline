import Integrations
import NotchShell
import SwiftUI

/// Zamanlayıcı: hazır süreler ya da Pomodoro; çalışırken büyük rakam, halka, +1 dk ve iptal.
struct TimerTab: View {
    let coordinator: AppCoordinator
    private var timer: CountdownTimer { coordinator.timer }

    private static let presets = [1, 5, 10, 25, 45]

    var body: some View {
        // Seçim ↔ geri sayım arası çapraz geçiş; rakamlar akarak azalır.
        ZStack {
            stateContent
                .id(timer.isRunning)
                .notchTransition(.swap)
        }
        .notchAnimation(value: timer.isRunning)
    }

    @ViewBuilder
    private var stateContent: some View {
        if timer.isRunning {
            // Saniyelik çizim yalnız sekme açıkken; kapanınca TimelineView da durur.
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let phase = coordinator.ui.pomodoroPhase
                HStack(spacing: 16) {
                    ProgressRing(progress: timer.progress(at: timeline.date), tint: phase?.tint ?? .orange)
                        .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(phase?.title ?? String(localized: "Zamanlayıcı"))
                            .font(NotchDesign.caption)
                            .foregroundStyle(.secondary)
                        let remaining = timer.remaining(at: timeline.date)
                        Text(CountdownTimer.format(remaining))
                            .font(NotchDesign.figure)
                            .contentTransition(.numericText(countsDown: true))
                            .notchAnimation(value: Int(remaining.rounded(.up)))
                    }
                    Spacer(minLength: 8)
                    Button("+1 dk") { timer.add(seconds: 60) }
                        .buttonStyle(CapsuleButtonStyle())
                    Button("İptal") { coordinator.cancelTimer() }
                        .buttonStyle(CapsuleButtonStyle())
                }
                .frame(maxHeight: .infinity)
            }
        } else {
            VStack(spacing: 10) {
                Text("Süre seçin").font(NotchDesign.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Button {
                        coordinator.startPomodoro()
                    } label: {
                        Label("Pomodoro", systemImage: "leaf.fill")
                    }
                    .buttonStyle(CapsuleButtonStyle(prominent: true, tint: .red))
                    .help("25 dk odak, 5 dk mola; dört turda bir 15 dk")
                    ForEach(Self.presets, id: \.self) { minutes in
                        Button("\(minutes) dk") { timer.start(seconds: TimeInterval(minutes * 60)) }
                            .buttonStyle(CapsuleButtonStyle())
                    }
                }
                if coordinator.settings.keepAwakeEnabled {
                    KeepAwakeToggle(keepAwake: coordinator.keepAwake)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Ekranı uyanık tutma: durum alanındaki fincan yalnız açıkken göründüğü için açma burada.
private struct KeepAwakeToggle: View {
    let keepAwake: KeepAwake

    var body: some View {
        Button {
            if keepAwake.isActive { keepAwake.stop() } else { keepAwake.start(reason: String(localized: "NotchMVP: uyanık tut")) }
        } label: {
            // Renk etiketin içinde: QuietButtonStyle kendi rengini dıştan verir, içteki kazanır.
            Label(keepAwake.isActive ? String(localized: "Uyanık tutuluyor · kapat") : String(localized: "Ekranı uyanık tut"),
                  systemImage: keepAwake.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                .foregroundStyle(keepAwake.isActive ? Color.orange : Color.white.opacity(0.6))
        }
        .buttonStyle(QuietButtonStyle())
        .help("Uyku ve ekran koruyucuyu engeller; süreli seçenekler menü çubuğunda")
        .notchAnimation(value: keepAwake.isActive)
    }
}

extension Pomodoro.Phase {
    var title: String {
        switch self {
        case let .focus(round): String(localized: "Odak · \(round). tur")
        case .shortBreak: String(localized: "Kısa mola")
        case .longBreak: String(localized: "Uzun mola")
        }
    }

    var tint: Color { isBreak ? .green : .red }
}
