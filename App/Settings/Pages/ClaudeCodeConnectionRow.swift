import Integrations
import SwiftUI

/// Claude Code bağlantısı: Browline'ın kancalarını tek tıkla ekler, günceller ya da kaldırır (`ClaudeCodeHooks`).
/// Onay penceresi neyin değişeceğini ve yedeği söyler; ayar dosyasında Browline dışındaki hiçbir şeye dokunulmaz.
/// Bağlanınca etkinlik API'si de açılır (kancalar onun soketine yazar).
struct ClaudeCodeConnectionRow: View {
    @Bindable var settings: AppSettings
    @State private var status: ClaudeCodeHooks.Status?
    @State private var pending: Action?
    @State private var result: (text: String, isError: Bool)?

    private enum Action { case connect, disconnect }

    private let paths = ClaudeCodeHooks.Paths.bundled()

    var body: some View {
        Group {
            HStack(spacing: 10) {
                SettingsIcon(symbol: "sparkles", tint: Color(red: 0.85, green: 0.47, blue: 0.34), size: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Claude Code bağlantısı")
                    Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if let status { pill(for: status) }
                buttons
            }
            .settingsAnchor("claudeCode")
            if let result {
                Text(verbatim: result.text)
                    .font(.caption)
                    .foregroundStyle(result.isError ? Color.red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear(perform: refresh)
        .confirmationDialog(dialogTitle, isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            if pending == .disconnect {
                Button("Kaldır", role: .destructive) { perform(.disconnect) }
            } else {
                Button(status == .needsUpdate ? "Güncelle" : "Bağla") { perform(.connect) }
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text(dialogMessage)
        }
    }

    @ViewBuilder
    private var buttons: some View {
        switch status {
        case .notConnected:
            Button("Bağla…") { pending = .connect }.controlSize(.small)
        case .needsUpdate:
            Button("Güncelle…") { pending = .connect }.controlSize(.small)
            Button("Kaldır…") { pending = .disconnect }.controlSize(.small)
        case .connected:
            Button("Kaldır…") { pending = .disconnect }.controlSize(.small)
        case .claudeNotFound, nil:
            Button("Yeniden dene", action: refresh).controlSize(.small)
        }
    }

    private var detail: LocalizedStringKey {
        switch status {
        case .connected: "İzin soruları, karar kartları ve oturum durumu notch'ta. Yeni Claude Code oturumlarında geçerli."
        case .notConnected: "Bağla, ~/.claude/settings.json dosyasına Browline'ın kancalarını ekler; diğer ayarlarınıza dokunmaz."
        case .needsUpdate: "Kancalar başka bir Browline'ı gösteriyor (uygulama taşınmış ya da elle kurulmuş). Güncelle, bu uygulamaya çevirir."
        case .claudeNotFound, nil: "Claude Code bu Mac'te hiç çalıştırılmamış (~/.claude yok). Önce bir kez çalıştırın."
        }
    }

    private func pill(for status: ClaudeCodeHooks.Status) -> some View {
        let (title, color): (LocalizedStringKey, Color) = switch status {
        case .connected: ("Bağlı", .green)
        case .notConnected: ("Bağlı değil", .blue)
        case .needsUpdate: ("Güncel değil", .orange)
        case .claudeNotFound: ("Bulunamadı", .secondary)
        }
        return Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(Capsule().fill(color.opacity(0.16)))
    }

    private var dialogTitle: LocalizedStringKey {
        pending == .disconnect ? "Claude Code bağlantısı kaldırılsın mı?" : "Claude Code'a bağlansın mı?"
    }

    private var dialogMessage: LocalizedStringKey {
        pending == .disconnect
            ? "Yalnız Browline'ın kancaları kaldırılır; önce ~/.claude/settings.json dosyasının yedeği alınır."
            : "Browline, ~/.claude/settings.json dosyasına altı kanca ekler: istem, araç, bildirim, tur sonu, oturum sonu ve izin istemi. Önce dosyanın yedeği alınır; diğer ayarlarınız ve kancalarınız değişmez. Yeni Claude Code oturumlarında geçerli olur."
    }

    private func refresh() {
        status = ClaudeCodeHooks.status(paths: paths)
    }

    private func perform(_ action: Action) {
        pending = nil
        guard action == .disconnect || FileManager.default.fileExists(atPath: paths.script.path) else {
            result = (String(localized: "Kanca betiği uygulamanın içinde yok; Browline'ı yeniden kurun."), true)
            return
        }
        do {
            let backup = action == .connect
                ? try ClaudeCodeHooks.connect(paths: paths)
                : try ClaudeCodeHooks.disconnect()
            if action == .connect { settings.activityAPIEnabled = true }
            let done = action == .connect
                ? String(localized: "Bağlandı. Açık Claude Code oturumları yeniden başlatılınca kancaları görür.")
                : String(localized: "Bağlantı kaldırıldı.")
            result = (backup.map { done + " " + String(localized: "Yedek: \($0.lastPathComponent)") } ?? done, false)
        } catch {
            result = (Self.message(for: error), true)
        }
        refresh()
    }

    private static func message(for error: ClaudeCodeHooks.Failure) -> String {
        switch error {
        case .claudeNotFound: String(localized: "Claude Code bulunamadı (~/.claude yok).")
        case .unreadable: String(localized: "~/.claude/settings.json okunamadı (geçersiz JSON); dosyaya dokunulmadı.")
        case .writeFailed: String(localized: "Dosya yazılamadı; eski hâli geri kondu.")
        }
    }
}
