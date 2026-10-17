import ActivityAPI
import NotchShell
import SwiftUI

/// Dış soru. Onay sorusu (ör. Claude Code izin istemi): başlık, araç ve proje, tam komut; Reddet ve İzin ver.
/// Seçenekli soru (Claude'un AskUserQuestion'ı): soru metni ve seçenek kartları; tek seçimde karta basmak
/// yanıtlar, çoklu seçimde işaretlenip Gönder'e basılır. Karar yalnız bu düğmelerle verilir. Notch soru gelince
/// kendiliğinden açıldığı için düğmeler ilk 0,8 sn pasif: o anda üst ortaya tıklayan yanlışlıkla yanıtlamasın.
/// "Claude'da yanıtla" soruyu bırakır, istemci kendi penceresini gösterir (serbest metin yanıtı için de).
/// Karar kartı (Claude masaüstünün turun sonundaki kutusu): soru, özet ve kutunun yanıt düğmeleri. Seçeneğe basınca
/// Browline Claude'daki aynı düğmeye basar; "Claude'da yanıtla" yalnız oturumu açar (kendi yanıtını yazmak için),
/// "Sonra" kartı kapatır.
struct QuestionView: View {
    let question: ExternalQuestion
    let waitingCount: Int
    let answer: (ActivityResponse.Decision?) -> Void
    let choose: ([Int]) -> Void
    /// Karar kartı: seçenek sırası (Claude'daki aynı düğmeye basılır) ya da nil (yalnız oturum açılır).
    let respond: (Int?) -> Void
    /// Karar kartında seçeneğe basıldı, Erişilebilirlik izni yok: seçenekler yerine izin adımları.
    var needsAccessibility = false
    var setUpAccessibility: () -> Void = {}
    @State private var isArmed = false
    @State private var selected: Set<Int> = []

    static let armDelay: Duration = .milliseconds(800)
    static let choiceRowHeight: CGFloat = 46

    /// İçerik boyu: onay sorusu sabit; seçenekli soruda iki sütunlu kart satırı başına artar.
    static func height(for question: ExternalQuestion?, needsAccessibility: Bool = false) -> CGFloat {
        if let question, question.isHandoff { return handoffHeight(for: question, needsAccessibility: needsAccessibility) }
        guard let question, question.isChoice else { return 156 }
        let rows = CGFloat((question.choices.count + 1) / 2)
        return 120 + rows * choiceRowHeight + (rows - 1) * 6
    }

    /// Karar kartı içeriğe göre: soru en çok 2, özet en çok 3 satır (satır başına yaklaşık karakter ile).
    static func handoffHeight(for question: ExternalQuestion, needsAccessibility: Bool = false) -> CGFloat {
        func lines(_ text: String?, perLine: Int, limit: Int) -> CGFloat {
            guard let text, !text.isEmpty else { return 0 }
            return CGFloat(min(limit, (text.count + perLine - 1) / perLine))
        }
        let ask = lines(question.detail, perLine: 75, limit: 2)
        // İzin adımları özetin yerine geçer: 3 satır ve daha büyük düğme payı.
        let context = needsAccessibility ? 3 : lines(question.context, perLine: 90, limit: 3)
        // Başlık, düğmeler ve aralıklar 58; soru satırı 17, özet satırı 15.
        return 58 + ask * 17 + (context > 0 ? 4 + context * 15 : 0) + (needsAccessibility ? 8 : 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if question.isHandoff {
                handoffBody
            } else if question.isChoice {
                choiceBody
            } else {
                approvalBody
            }
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

    @ViewBuilder
    private var handoffBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let ask = question.detail, !ask.isEmpty {
                Text(verbatim: ask).font(NotchDesign.bodyEmphasized).lineLimit(2)
            }
            if needsAccessibility {
                // Sistemin istemi macOS 27'de uygulamayı listeye eklemedi; adımlar bölmenin bu Mac'teki adıyla.
                Text("Claude'daki düğmeye basmak için izin gerekli. İzin ver… Gizlilik ve Güvenlik › \(PermissionKind.accessibility.systemName) bölmesini ve Finder'da Browline'ı açar: Browline'ı listeye sürükleyip anahtarını açın.")
                    .font(NotchDesign.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            } else if let context = question.context, !context.isEmpty {
                Text(verbatim: context).font(NotchDesign.caption).foregroundStyle(.secondary).lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .textSelection(.enabled)
        HStack(spacing: 8) {
            Button("Sonra") { answer(nil) }
                .buttonStyle(QuietButtonStyle())
                .help("Yalnız kartı kapatır; soru Claude'da bekler")
            Spacer(minLength: 8)
            if needsAccessibility {
                Button("Claude'da yanıtla") { respond(nil) }
                    .buttonStyle(QuietButtonStyle())
                    .help("Oturumu Claude'da açar; yanıtı orada verirsiniz")
                Button("İzin ver…") { setUpAccessibility() }
                    .buttonStyle(CapsuleButtonStyle(prominent: true, tint: .blue))
                    .help("İzin bölmesini ve Finder'da Browline'ı açar")
            } else if question.choices.isEmpty {
                Button("Claude'da yanıtla") { respond(nil) }
                    .buttonStyle(CapsuleButtonStyle(prominent: true, tint: tint))
                    .disabled(!isArmed)
                    .help("Oturumu Claude'da açar")
            } else {
                Button("Claude'da yanıtla") { respond(nil) }
                    .buttonStyle(QuietButtonStyle())
                    .help("Oturumu Claude'da açar; kendi yanıtını yazmak için")
                // Kutunun yanıt düğmeleri; ilki Claude'un önerisi.
                ForEach(Array(question.choices.prefix(3).enumerated()), id: \.offset) { index, label in
                    Button { respond(index) } label: { Text(verbatim: label).lineLimit(1) }
                        .buttonStyle(CapsuleButtonStyle(prominent: index == 0, tint: tint))
                        .disabled(!isArmed)
                        .help("Claude'daki aynı düğmeye basar (Erişilebilirlik izni gerekir)")
                }
            }
        }
        .opacity(isArmed ? 1 : 0.6)
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
            // Kalan süre: dolunca soru düşer ve istemci kendi penceresini gösterir. Karar kartında kimse beklemiyor.
            if !question.isHandoff {
                countdown
            }
        }
    }

    private var countdown: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let remaining = max(0, Int(question.expiresAt.timeIntervalSince(timeline.date).rounded(.up)))
            Text(verbatim: String(format: "%d:%02d", remaining / 60, remaining % 60))
                .font(NotchDesign.caption.monospacedDigit())
                .foregroundStyle(.secondary)
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
