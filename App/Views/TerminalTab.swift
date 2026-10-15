import AppKit
import NotchShell
import SwiftTerm
import SwiftUI

/// Terminal sekmesi: gerçek kabuk (SwiftTerm). Sekme görünürken panel klavye alabilir; yazmak için
/// terminale tıklanır (sekmeye tıklayarak açıldıysa doğrudan yazılır). Odaklanınca notch sabitlenir;
/// dışarı tıklama kapatır. Esc, Ctrl tuşları ve oklar kabuğa gider; ⌘C, ⌘V, ⌘A çalışır.
struct TerminalTab: View {
    let session: TerminalSession
    let model: NotchSurfaceModel

    var body: some View {
        ZStack {
            if let view = session.view {
                TerminalHost(view: view) { model.tapped() }
                    .padding(.leading, 8)
                    .padding(.vertical, 6)
            }
            if let status = session.exitStatus {
                EmptyStateView(symbol: "terminal",
                               title: "Kabuk kapandı",
                               message: status >= 0 ? LocalizedStringKey("Çıkış kodu \(status)") : nil) {
                    Button("Yeniden başlat") { session.restart() }
                        .buttonStyle(CapsuleButtonStyle(prominent: true, tint: .blue))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.85))
                .notchTransition(.fade)
            }
        }
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: NotchDesign.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NotchDesign.cardRadius, style: .continuous)
            .strokeBorder(NotchDesign.cardFill, lineWidth: 1))
        .notchAnimation(value: session.exitStatus)
        .onAppear {
            model.wantsKeyboard = true
            session.startIfNeeded()
        }
        .onDisappear { model.wantsKeyboard = false }
    }
}

/// Tek terminal görünümünü kendi kabına taşır: sekme kapanıp açılınca ya da başka ekranda
/// açılınca oturum ve tampon aynı kalır.
private struct TerminalHost: NSViewRepresentable {
    let view: LocalProcessTerminalView
    let onFocus: () -> Void

    func makeNSView(context: Context) -> TerminalContainerView {
        let container = TerminalContainerView()
        container.attach(view)
        container.onFocus = onFocus
        return container
    }

    func updateNSView(_ container: TerminalContainerView, context: Context) {
        if view.superview !== container { container.attach(view) }
        container.onFocus = onFocus
    }

    static func dismantleNSView(_ container: TerminalContainerView, coordinator: ()) {
        container.detach()
    }
}

/// Terminalin kabı. Pencerenin ilk yanıtlayıcısı terminal olunca (tıklandı) notch sabitlenir;
/// sekme bilinçli bir tıklamayla (panel key) açıldıysa doğrudan yazılır, üzerine gelerek
/// açıldıysa klavye öndeki uygulamada kalır.
final class TerminalContainerView: NSView {
    var onFocus: (() -> Void)?
    private weak var terminal: LocalProcessTerminalView?
    private var observation: NSKeyValueObservation?

    /// Kap ilk anda sıfır boyutlu; terminal ona göre küçülürse kabuk SIGWINCH alıyor, satırlar
    /// yeniden akıyor ve içerik bozuluyordu. Boyut yalnız kap gerçek boyuta gelince verilir.
    func attach(_ view: LocalProcessTerminalView) {
        subviews.forEach { $0.removeFromSuperview() }
        view.removeFromSuperview()
        view.autoresizingMask = []
        if !bounds.isEmpty { view.frame = bounds }
        addSubview(view)
        terminal = view
        refresh()
        focusIfKey()
    }

    override func layout() {
        super.layout()
        guard let terminal, !bounds.isEmpty, terminal.frame != bounds else { return }
        terminal.frame = bounds
    }

    func detach() {
        observation = nil
        if let terminal, terminal.superview === self { terminal.removeFromSuperview() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observation = window?.observe(\.firstResponder, options: [.new]) { [weak self] window, _ in
            MainActor.assumeIsolated {
                guard let self, let terminal = self.terminal, window.firstResponder === terminal else { return }
                self.onFocus?()
            }
        }
        refresh()
        focusIfKey()
    }

    /// Pencere dışındayken gelen çıktı tampona yazılıyor ama görünüm geri gelince ekran ve imleç
    /// bayat kalıyordu (2026-10-16: arka planda biten `ping`'in çıktısı görünmedi). Tam yeniden çizim.
    private func refresh() {
        guard window != nil, let terminal else { return }
        terminal.getTerminal().updateFullScreen()
        terminal.feed(text: "")
        terminal.needsDisplay = true
    }

    private func focusIfKey() {
        guard let window, window.isKeyWindow, let terminal else { return }
        window.makeFirstResponder(terminal)
    }
}
