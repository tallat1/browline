import AppKit
import Observation
import SwiftTerm

/// Notch terminali: tek kabuk oturumu (kullanıcının giriş kabuğu, ev dizininde). Notch kapanınca ya
/// da sekme değişince yaşamaya devam eder; görünüm tek örnek, açık sekme onu kendi içine taşır.
/// Kabuk sekme ilk açılınca başlar, modül kapatılınca ya da uygulama kapanınca sonlanır.
@MainActor
@Observable
final class TerminalSession {
    /// Kabuk çıktıysa çıkış kodu (bilinmiyorsa -1); sekme "yeniden başlat" gösterir.
    private(set) var exitStatus: Int32?
    /// Her başlatmada yeni görünüm: yeniden başlatınca eski tampon gider.
    private(set) var view: LocalProcessTerminalView?
    @ObservationIgnored private var delegateProxy: ProcessDelegateProxy?
    @ObservationIgnored private var generation = 0

    var isRunning: Bool { view != nil && exitStatus == nil }

    /// Tanı: sütun × satır.
    var gridSize: (columns: Int, rows: Int)? {
        view.map { ($0.getTerminal().cols, $0.getTerminal().rows) }
    }

    func startIfNeeded() {
        guard view == nil else { return }
        launch()
    }

    func restart() {
        if isRunning { view?.terminate() }
        launch()
    }

    func stop() {
        guard let view else { return }
        generation += 1
        if exitStatus == nil { view.terminate() }
        view.removeFromSuperview()
        self.view = nil
        exitStatus = nil
        AppLog.coordinator.notice("terminal: kabuk kapatıldı")
    }

    private func launch() {
        generation += 1
        let current = generation
        let terminal = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 620, height: 260))
        Self.configure(terminal)
        let proxy = ProcessDelegateProxy { [weak self] code in
            guard let self, self.generation == current else { return }
            self.exitStatus = code ?? -1
            AppLog.coordinator.notice("terminal: kabuk çıktı (\(code ?? -1))")
        }
        terminal.processDelegate = proxy
        delegateProxy = proxy
        let shell = Self.loginShell
        // argv[0] "-zsh": giriş kabuğu (profil dosyaları okunur, PATH path_helper'dan gelir).
        terminal.startProcess(executable: shell, args: [], environment: Self.environment(shell: shell),
                              execName: "-" + (shell as NSString).lastPathComponent,
                              currentDirectory: FileManager.default.homeDirectoryForCurrentUser.path)
        view?.removeFromSuperview()
        view = terminal
        exitStatus = nil
        AppLog.coordinator.notice("terminal: kabuk başladı (\(shell, privacy: .public))")
    }

    private static func configure(_ terminal: LocalProcessTerminalView) {
        terminal.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        terminal.nativeBackgroundColor = .black
        terminal.nativeForegroundColor = NSColor(white: 0.92, alpha: 1)
        terminal.caretColor = .white
        // Türkçe Q klavyede @ # [ ] { } | \ ~ Option ile yazılır; Meta olursa yazılamaz.
        terminal.optionAsMetaKey = false
        // SwiftTerm kaydırma çubuğunu "legacy" kuruyor (gri iz) ve NSScrollView dışında olduğu için
        // kendiliğinden gizlenmiyor; gizli. Geçmişe iki parmakla kaydırma görünümde çalışır.
        for case let scroller as NSScroller in terminal.subviews {
            scroller.isHidden = true
        }
    }

    /// Kullanıcı hesabındaki kabuk (Dizin Hizmetleri); bulunamazsa zsh.
    private static var loginShell: String {
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            let path = String(cString: shell)
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return "/bin/zsh"
    }

    /// Terminal.app'e yakın ortam: renk, dil, ev, kullanıcı ve ssh-agent soketi (git için).
    private static func environment(shell: String) -> [String] {
        let inherited = ProcessInfo.processInfo.environment
        var variables = Terminal.getEnvironmentVariables(termName: "xterm-256color", trueColor: true)
            .filter { !$0.hasPrefix("LANG=") }
        variables.append("LANG=\(localeName)")
        variables.append("SHELL=\(shell)")
        variables.append("TERM_PROGRAM=NotchMVP")
        // bash'in "varsayılan kabuk artık zsh" uyarısı küçük alanı dolduruyor.
        variables.append("BASH_SILENCE_DEPRECATION_WARNING=1")
        for key in ["PATH", "TMPDIR", "SSH_AUTH_SOCK"] {
            if let value = inherited[key] { variables.append("\(key)=\(value)") }
        }
        return variables
    }

    /// Sistem dilinin UTF-8 yereli (ör. tr_TR.UTF-8); sistemde yoksa en_US.UTF-8.
    private static var localeName: String {
        let locale = Locale.current
        if let language = locale.language.languageCode?.identifier, let region = locale.region?.identifier {
            let name = "\(language)_\(region).UTF-8"
            if FileManager.default.fileExists(atPath: "/usr/share/locale/\(name)") { return name }
        }
        return "en_US.UTF-8"
    }
}

/// SwiftTerm temsilcisi ana aktöre bağlı değil; yalnız kabuğun çıkışı ana kuyruğa iletilir.
private final class ProcessDelegateProxy: LocalProcessTerminalViewDelegate {
    private let onExit: @MainActor (Int32?) -> Void

    init(onExit: @escaping @MainActor (Int32?) -> Void) {
        self.onExit = onExit
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        AppLog.coordinator.notice("terminal: ızgara \(newCols)×\(newRows)")
    }
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        let onExit = onExit
        DispatchQueue.main.async {
            MainActor.assumeIsolated { onExit(exitCode) }
        }
    }
}
