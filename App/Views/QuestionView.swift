import ActivityAPI
import NotchShell
import SwiftUI

/// Dış onay sorusu (ör. Claude Code izin istemi): başlık, araç ve proje, tam komut; Reddet ve İzin ver.
/// Karar yalnız bu düğmelerle verilir. Notch soru gelince kendiliğinden açıldığı için düğmeler ilk
/// 0,8 sn pasif: o anda üst ortaya tıklayan kullanıcı yanlışlıkla izin vermesin. "Claude'da yanıtla"
/// soruyu bırakır, istemci kendi penceresini gösterir.
struct QuestionView: View {
    let question: ExternalQuestion
    let waitingCount: Int
    let answer: (ActivityResponse.Decision?) -> Void
    @State private var isArmed = false

    static let height: CGFloat = 156
    static let armDelay: Duration = .milliseconds(800)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let detail = question.detail, !detail.isEmpty {
                ScrollView {
                    Text(verbatim: detail)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 52)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: NotchDesign.Radius.medium, style: .continuous)
                    .fill(NotchDesign.cardFill))
                .overlay(RoundedRectangle(cornerRadius: NotchDesign.Radius.medium, style: .continuous)
                    .strokeBorder(NotchDesign.hairline, lineWidth: 0.5))
            }
            HStack(spacing: 8) {
                Button(isClaude ? "Claude'da yanıtla" : "Atla") { answer(nil) }
                    .buttonStyle(QuietButtonStyle())
                    .help("Soruyu bırakır; karar uygulamanın kendi penceresinde verilir")
                Spacer(minLength: 8)
                Button("Reddet") { answer(.deny) }
                    .buttonStyle(CapsuleButtonStyle())
                    .disabled(!isArmed)
                Button("İzin ver") { answer(.allow) }
                    .buttonStyle(CapsuleButtonStyle(prominent: true, tint: .green))
                    .disabled(!isArmed)
                    .help("Yalnız bu istek için")
            }
            .opacity(isArmed ? 1 : 0.6)
            .notchAnimation(value: isArmed)
        }
        .task(id: question.id) {
            isArmed = false
            try? await Task.sleep(for: Self.armDelay)
            isArmed = true
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: question.symbol ?? "hand.raised.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(Circle().fill(tint.opacity(0.18)))
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: question.title).font(NotchDesign.bodyEmphasized).lineLimit(1)
                if let subtitle = question.subtitle {
                    Text(verbatim: subtitle).font(NotchDesign.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if waitingCount > 1 {
                Text(verbatim: "+\(waitingCount - 1)")
                    .font(NotchDesign.captionEmphasized)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(NotchDesign.selectionFill))
                    .help("Bekleyen diğer sorular")
            }
            // Kalan süre: dolunca soru düşer ve istemci kendi penceresini gösterir.
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let remaining = max(0, Int(question.expiresAt.timeIntervalSince(timeline.date).rounded(.up)))
                Text(verbatim: String(format: "%d:%02d", remaining / 60, remaining % 60))
                    .font(NotchDesign.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var isClaude: Bool { question.id.hasPrefix("claude-perm-") }

    private var tint: Color {
        guard let hex = question.tint, hex.count == 7, let value = Int(hex.dropFirst(), radix: 16) else { return .orange }
        return Color(.sRGB, red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                     blue: Double(value & 0xFF) / 255)
    }
}
