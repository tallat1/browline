import ActivityAPI
import NotchShell
import SwiftUI

/// Dış soru. Onay sorusu (ör. Claude Code izin istemi): başlık, araç ve proje, tam komut; Reddet ve İzin ver.
/// Seçenekli soru (Claude'un AskUserQuestion'ı): soru metni ve seçenek kartları; tek seçimde karta basmak
/// yanıtlar, çoklu seçimde işaretlenip Gönder'e basılır. Karar yalnız bu düğmelerle verilir. Notch soru gelince
/// kendiliğinden açıldığı için düğmeler ilk 0,8 sn pasif: o anda üst ortaya tıklayan yanlışlıkla yanıtlamasın.
/// "Claude'da yanıtla" soruyu bırakır, istemci kendi penceresini gösterir (serbest metin yanıtı için de).
struct QuestionView: View {
    let question: ExternalQuestion
    let waitingCount: Int
    let answer: (ActivityResponse.Decision?) -> Void
    let choose: ([Int]) -> Void
    @State private var isArmed = false
    @State private var selected: Set<Int> = []

    static let armDelay: Duration = .milliseconds(800)
    static let choiceRowHeight: CGFloat = 46

    /// İçerik boyu: onay sorusu sabit; seçenekli soruda iki sütunlu kart satırı başına artar.
    static func height(for question: ExternalQuestion?) -> CGFloat {
        guard let question, question.isChoice else { return 156 }
        let rows = CGFloat((question.choices.count + 1) / 2)
        return 120 + rows * choiceRowHeight + (rows - 1) * 6
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if question.isChoice { choiceBody } else { approvalBody }
        }
        .task(id: question.id) {
            isArmed = false
            selected = []
            try? await Task.sleep(for: Self.armDelay)
            isArmed = true
        }
    }

    @ViewBuilder
    private var approvalBody: some View {
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

    @ViewBuilder
    private var choiceBody: some View {
        if let text = question.detail, !text.isEmpty {
            Text(verbatim: text)
                .font(NotchDesign.body)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
            ForEach(question.choices.indices, id: \.self) { index in
                ChoiceCard(label: question.choices[index],
                           detail: question.choiceDetails.indices.contains(index) ? question.choiceDetails[index] : "",
                           isMultiple: question.allowsMultiple, isSelected: selected.contains(index)) {
                    if question.allowsMultiple {
                        if selected.remove(index) == nil { selected.insert(index) }
                    } else {
                        choose([index])
                    }
                }
                .frame(height: Self.choiceRowHeight)
                .disabled(!isArmed)
            }
        }
        .opacity(isArmed ? 1 : 0.6)
        HStack(spacing: 8) {
            Button("Claude'da yanıtla") { answer(nil) }
                .buttonStyle(QuietButtonStyle())
                .help("Soruyu bırakır; Claude kendi penceresinde sorar (kendi yanıtını yazmak için de)")
            Spacer(minLength: 8)
            if question.allowsMultiple {
                Button("Gönder") { choose(selected.sorted()) }
                    .buttonStyle(CapsuleButtonStyle(prominent: true, tint: .green))
                    .disabled(!isArmed || selected.isEmpty)
            }
        }
        .notchAnimation(value: isArmed)
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

/// Seçenek kartı: etiket ve kısa açıklama; çoklu seçimde işaret kutusu.
private struct ChoiceCard: View {
    let label: String
    let detail: String
    let isMultiple: Bool
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 8) {
                if isMultiple {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSelected ? Color.green : .secondary)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: label).font(NotchDesign.bodyEmphasized).lineLimit(1)
                    if !detail.isEmpty {
                        Text(verbatim: detail).font(NotchDesign.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: NotchDesign.Radius.medium, style: .continuous)
                .fill(isSelected ? NotchDesign.selectionFill : isHovering ? NotchDesign.cardHoverFill : NotchDesign.cardFill))
            .overlay(RoundedRectangle(cornerRadius: NotchDesign.Radius.medium, style: .continuous)
                .strokeBorder(isSelected ? Color.green.opacity(0.6) : NotchDesign.hairline, lineWidth: isSelected ? 1 : 0.5))
            .contentShape(RoundedRectangle(cornerRadius: NotchDesign.Radius.medium, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(detail.isEmpty ? label : "\(label): \(detail)")
    }
}
