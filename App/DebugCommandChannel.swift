#if DEBUG
import ActivityAPI
import AppKit
import Integrations
import NotchShell
import os

private let debugLog = Logger(subsystem: "com.talatozcoban.notchmvp", category: "debug")

/// Yalnız debug derlemesi: test betikleri notch'u imleci ele geçirmeden yönetebilsin.
/// Komutlar dağıtık bildirim nesnesi olarak gelir: open, close, tab:media|calendar|shelf|activities,
/// flash:power, hud:preview, state, lock:on|lock:off (kilit benzetimi, SkyLight kullanmaz),
/// display:floating|off|reset (birinci ekranın modu), timer:<sn>|cancel, audio:preview, track:preview,
/// awake:on|off, battery:low|full, weather:<şehir>|off, timer:pomodoro.
@MainActor
final class DebugCommandChannel {
    static let name = Notification.Name("com.talatozcoban.notchmvp.debug")
    private let coordinator: AppCoordinator
    private var token: NSObjectProtocol?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    func start() {
        token = DistributedNotificationCenter.default().addObserver(forName: Self.name, object: nil,
                                                                    queue: .main) { [weak self] note in
            let command = note.object as? String ?? ""
            MainActor.assumeIsolated { self?.handle(command) }
        }
    }

    private func handle(_ command: String) {
        let models = coordinator.panels.models
        switch command {
        case let page where page.hasPrefix("settings:page:"):
            // settings:page:<sayfa>[:<vurgu>]
            let parts = page.dropFirst(14).split(separator: ":").map(String.init)
            if let value = parts.first.flatMap(SettingsPage.init(rawValue:)) {
                coordinator.ui.settingsPage = value
                coordinator.ui.settingsHighlight = parts.count > 1 ? parts[1] : nil
            }
        case "onboarding:show":
            coordinator.openOnboarding?()
        case "onboarding:close":
            coordinator.closeOnboarding?()
        case let step where step.hasPrefix("onboarding:step:"):
            if let value = Int(step.dropFirst(16)) { coordinator.onboardingStepForDebug?(value) }
        case "system:fill-history":
            // Yapay 600 nokta: grafik çizim maliyetini dolu geçmişle ölçmek için.
            coordinator.systemStats.fillHistoryForMeasurement()
        case "notch:hide":
            coordinator.hideNotch(for: 3600)
        case "notch:show":
            coordinator.showNotch()
        case "menu:show":
            coordinator.showStatusMenuForCapture?()
        case "settings:open":
            coordinator.openSettings?()
        case "settings:close":
            coordinator.closeSettings?()
        case "open":
            models.forEach { $0.tapped() }
        case "close":
            models.forEach { $0.dismiss() }
        case "shelf:add-test":
            // Yalnız deneme dosyası; kullanıcının raf öğelerine dokunmaz.
            let file = URL(fileURLWithPath: "/tmp/notch-raf-deneme.txt")
            try? "NotchMVP raf denemesi".write(to: file, atomically: true, encoding: .utf8)
            coordinator.shelf.add([file])
        case "shelf:remove-test":
            // Raf çözülmüş yolu (/private/tmp) tutabiliyor: önekle değil dosya kimliğiyle.
            let test = ShelfStore.identity(of: URL(fileURLWithPath: "/tmp/notch-raf-deneme.txt"))
            for item in coordinator.shelf.items where ShelfStore.identity(of: item.url) == test {
                coordinator.shelf.remove(item.id)
            }
        case "mic:state":
            let microphone = coordinator.microphone
            let summary = "sessiz \(microphone.isMuted), yazılabilir \(microphone.canMute), kullanan [\(microphone.inputApps.map(\.name).joined(separator: ", "))]"
            AppLog.coordinator.notice("mikrofon durumu: \(summary, privacy: .public)")
        case "spectrum:state":
            let spectrum = coordinator.spectrum
            let reading = spectrum.levels.read()
            let values = reading.values.map { String(format: "%.2f", $0) }.joined(separator: " ")
            let summary = "açık \(spectrum.isEnabled), çalışıyor \(spectrum.isRunning), sinyal \(reading.hasSignal), [\(values)], hata \(spectrum.lastError ?? "yok")"
            AppLog.coordinator.notice("spektrum: \(summary, privacy: .public)")
        case "spectrum:probe-on":
            // Çubuk görünmese de dinleyiciyi tutar (ölçüm için); probe-off ile bırakılır.
            coordinator.spectrum.acquire()
        case "spectrum:probe-off":
            coordinator.spectrum.release()
        case "mic:shortcut":
            // Kısayola basılmış gibi: gerçekten sessize alır; yalnız mikrofon boştayken, iki kez gönder.
            coordinator.toggleMicrophoneFromShortcut()
        case "power:low-on", "power:low-off", "power:low-auto":
            // Sistemi değiştirmeden Düşük Güç Modu benzetimi.
            coordinator.lowPower.override = command == "power:low-auto" ? nil : command == "power:low-on"
        case "ci:state":
            let ci = coordinator.ci
            let summary = "durum \(String(describing: ci.status)), çalışma \(ci.runs.count), süren \(ci.activeRuns.count)"
            AppLog.coordinator.notice("CI durumu: \(summary, privacy: .public)")
        case "ci:preview-start", "ci:preview-done", "ci:preview-fail":
            // Örnek çalışma: depo ve iş akışı adı deneme olduğunu söyler; yalnız bellekte.
            let started = Date.now.addingTimeInterval(-95)
            func sample(_ state: CIMonitor.Run.State) -> CIMonitor.Run {
                CIMonitor.Run(id: -1, repository: "ornek/deneme-depo", workflow: "Örnek iş akışı", title: "Deneme commit'i",
                              branch: "main", state: state, createdAt: started, url: nil)
            }
            switch command {
            case "ci:preview-start": coordinator.ci.preview([sample(.active)])
            case "ci:preview-fail": coordinator.ci.preview([sample(.active)]); coordinator.ci.preview([sample(.failure)])
            default: coordinator.ci.preview([sample(.active)]); coordinator.ci.preview([sample(.success)])
            }
        case "ci:preview-clear":
            coordinator.ci.preview([])
        case "ci:suggest":
            // Yalnız okur: ~/GitHub altındaki depoların origin adresleri ve son commit zamanı.
            let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("GitHub")
            Task {
                let found = await Task.detached { CIMonitor.suggestedRepositories(in: root) }.value
                AppLog.coordinator.notice("CI önerileri: \(found.joined(separator: ", "), privacy: .public)")
            }
        case "mic:toggle":
            coordinator.microphone.toggleMute()
        case "bluetooth:state":
            // Ad yazılmaz: tür ve pil düzeyleri.
            let summary = coordinator.bluetooth.devices
                .map { "\($0.kind.rawValue) \($0.lowest.map(String.init) ?? "–")" }
                .joined(separator: ", ")
            let running = coordinator.bluetooth.isRunning
            AppLog.coordinator.notice("bluetooth: çalışıyor \(running), [\(summary, privacy: .public)]")
        case "bluetooth:preview-connect", "bluetooth:preview-low", "bluetooth:preview-disconnect":
            // Örnek aygıt; adı deneme olduğunu söyler.
            let sample = BluetoothMonitor.Device(name: "Örnek kulaklık (deneme)", kind: .headphones,
                                                 left: 12, right: 64, caseLevel: 40)
            let change: BluetoothEvent.Change = switch command {
            case "bluetooth:preview-low": .lowBattery(12)
            case "bluetooth:preview-disconnect": .disconnected
            default: .connected
            }
            coordinator.flashBluetooth(sample, change)
        case "clipboard:state":
            // İçerik yazılmaz: yalnız sayı ve türler.
            let kinds = coordinator.clipboard.items.map { item -> String in
                switch item.content {
                case .text: "metin"
                case .url: "bağlantı"
                case .files: "dosya"
                case .image: "görsel"
                }
            }
            let running = coordinator.clipboard.isRunning
            let blocked = coordinator.clipboard.isReadingBlocked
            debugLog.info("pano geçmişi: \(kinds.count) öğe [\(kinds.joined(separator: ", "), privacy: .public)], çalışıyor \(running), engelli \(blocked)")
        case let section where section.hasPrefix("section:"):
            if let value = NotchSection(rawValue: String(section.dropFirst(8))) { coordinator.select(value) }
        case let tab where tab.hasPrefix("tab:"):
            // "media" eski ad: Şimdi.
            let name = String(tab.dropFirst(4))
            if let value = NotchTab(rawValue: name == "media" ? "now" : name) { coordinator.ui.selectedTab = value }
        case "flash:power":
            coordinator.activities.flash(AppCoordinator.ActivityKind.power, duration: .seconds(3))
        case "hud:preview":
            coordinator.hud.previewCurrentVolume()
            let hud = coordinator.hud
            debugLog.info("HUD önizleme: düzey \(hud.level, privacy: .public), sessiz \(hud.isMuted, privacy: .public)")
        case "lock:on", "lock:off":
            let accepted = coordinator.lockScreen.simulateLock(command == "lock:on")
            debugLog.info("kilit benzetimi \(command, privacy: .public): \(accepted ? "uygulandı" : "reddedildi (özellik açık)", privacy: .public)")
        case "display:floating", "display:off", "display:reset":
            // Birinci ekranın (yerleşik) modunu dener; reset seçimi siler, önceki duruma döner.
            guard let display = PanelManager.displaySummaries(for: coordinator.settings.panelOptions).first else { break }
            let mode = PanelManager.DisplayMode(rawValue: String(command.dropFirst("display:".count)))
            coordinator.settings.displayModes[display.persistentID] = mode
            debugLog.info("ekran modu \(command, privacy: .public): \(display.name, privacy: .public)")
        case let timer where timer.hasPrefix("timer:"):
            if timer == "timer:cancel" { coordinator.cancelTimer() }
            else if timer == "timer:pomodoro" { coordinator.startPomodoro() }
            else if let seconds = Double(timer.dropFirst(6)) { coordinator.timer.start(seconds: seconds) }
        case "audio:preview":
            coordinator.activities.flash(AppCoordinator.ActivityKind.audioOutput, duration: .seconds(3))
        case "track:preview":
            let title = coordinator.nowPlaying.info?.title ?? ""
            coordinator.activities.flash(AppCoordinator.ActivityKind.trackChange,
                                         duration: AppCoordinator.trackPeekDuration(for: title))
        case "awake:on":
            coordinator.keepAwake.start(for: .seconds(90), reason: "NotchMVP debug")
        case "awake:off":
            coordinator.keepAwake.stop()
        case "awake:forever":
            coordinator.keepAwake.start(reason: "NotchMVP debug")
        case let command where command.hasPrefix("awake:"):
            // awake:<saniye>: süre dolumunu kısa sürede sınamak için.
            if let seconds = Int(command.dropFirst("awake:".count)), seconds > 0 {
                coordinator.keepAwake.start(for: .seconds(seconds), reason: "NotchMVP debug")
            }
        case "battery:low":
            coordinator.activities.flash(AppCoordinator.ActivityKind.batteryLow, duration: .seconds(4))
        case "battery:full":
            coordinator.activities.flash(AppCoordinator.ActivityKind.batteryFull, duration: .seconds(4))
        case let command where command.hasPrefix("weather:"):
            // Ayarları değiştirmeden dener; ayar kapalıysa sonraki ayar değişikliği durdurur.
            let city = String(command.dropFirst("weather:".count))
            if city == "off" { coordinator.weather.stop(); break }
            Task { @MainActor in
                if let place = try? await WeatherMonitor.geocode(city) { coordinator.weather.start(place: place) }
            }
        case "claude:limit-preview":
            // ÖRNEK veri: 2 sa 13 dk sonra sıfırlanacak 5 saatlik limit.
            coordinator.claudeUsage.previewLimit([ClaudeLimitHit(type: "five_hour",
                                                                 resetsAt: .now.addingTimeInterval(7_980), hitAt: .now)])
        case "media:drift":
            // Salt okunur: gösterilen konum ile Spotify/Music'in gerçek konumu.
            Task { @MainActor in
                let info = coordinator.nowPlaying.info
                if let drift = await coordinator.nowPlaying.measureDrift() {
                    let raw = "örnek konum \(info?.elapsedTime.map { String(format: "%.2f", $0) } ?? "-") @ \(info?.timestamp.map { String(format: "%.1f sn önce", Date.now.timeIntervalSince($0)) } ?? "-"), hız \(info?.playbackRate ?? 0)"
                    debugLog.info("konum kayması: gösterilen \(String(format: "%.2f", drift.shown), privacy: .public), gerçek \(String(format: "%.2f", drift.actual), privacy: .public), fark \(String(format: "%+.2f", drift.shown - drift.actual), privacy: .public) sn [\(info?.title ?? "", privacy: .public); \(raw, privacy: .public)]")
                } else {
                    debugLog.info("konum kayması ölçülemedi (Spotify/Music değil ya da kapalı)")
                }
            }
        case let command where command.hasPrefix("question:test-answer:"):
            // Yalnız deneme soruları (kimliği "notch-test-" ile başlayan): dağıtık bildirimi her süreç
            // gönderebildiği için gerçek bir onay (Claude izni) buradan asla verilemez.
            guard let question = coordinator.questions.current, question.id.hasPrefix("notch-test-") else {
                debugLog.error("deneme yanıtı reddedildi: bekleyen deneme sorusu yok")
                break
            }
            let value = String(command.dropFirst("question:test-answer:".count))
            coordinator.questions.answer(question.id, with: ActivityResponse.Decision(rawValue: value))
            debugLog.info("deneme sorusu yanıtlandı: \(value, privacy: .public)")
        case "terminal:state":
            // Salt okunur: kabuğa bir şey yazmaz.
            let terminal = coordinator.terminal
            let grid = terminal.gridSize.map { "\($0.columns)×\($0.rows)" } ?? "-"
            let window = terminal.view?.window
            debugLog.info("terminal: çalışıyor \(terminal.isRunning), ızgara \(grid, privacy: .public), pencerede \(window != nil), key \(window?.isKeyWindow ?? false), odak \(window?.firstResponder === terminal.view)")
        case "terminal:feed-test":
            // Yalnız ekrana yazar (kabuğa gitmez): pencere dışındayken gelen çıktı geri gelince görünüyor mu.
            let stamp = Date.now.formatted(date: .omitted, time: .standard)
            coordinator.terminal.view?.feed(text: "\r\n[NotchMVP deneme] pencere dışındayken yazıldı \(stamp)\r\n")
            let attached = coordinator.terminal.view?.window != nil
            debugLog.info("terminal deneme satırı yazıldı (\(stamp, privacy: .public)), pencerede \(attached)")
        case "terminal:check":
            // Salt okunur ve içerik yazmadan: deneme satırı tamponda mı, imleç nerede.
            guard let view = coordinator.terminal.view else { break }
            let terminal = view.getTerminal()
            let rows = (0..<terminal.rows).compactMap { terminal.getLine(row: $0)?.translateToString(trimRight: true) }
            let markerRow = rows.firstIndex { $0.contains("[NotchMVP deneme]") } ?? -1
            let cursor = terminal.getCursorLocation()
            let used = rows.filter { !$0.isEmpty }.count
            debugLog.info("terminal tamponu: deneme satırı \(markerRow), dolu satır \(used), imleç \(cursor.x),\(cursor.y)")
        case "sessions":
            let nowPlaying = coordinator.nowPlaying
            let list = nowPlaying.sessions.map { "\($0.id) \($0.info.isPlaying ? "▶" : "⏸") \($0.info.title)" }
            debugLog.info("oturumlar (odak \(nowPlaying.focusedSessionID ?? "-", privacy: .public)): \(list.joined(separator: " | "), privacy: .public)")
        case let command where command.hasPrefix("session:"):
            // Yalnız gösterilen oturumu değiştirir; çalmaya dokunmaz.
            if let index = Int(command.dropFirst("session:".count)), coordinator.nowPlaying.sessions.indices.contains(index) {
                coordinator.nowPlaying.selectSession(coordinator.nowPlaying.sessions[index].id)
            }
        case "state":
            let summary = "gizlilik [\(coordinator.privacy.deviceSummary)], HUD \(coordinator.hud.mode.rawValue), "
                + "indirmeler \(coordinator.downloads.isRunning ? "açık" : "kapalı"), "
                + "kilit ekranı \(coordinator.lockScreen.status) (kilitli: \(coordinator.lockScreen.isLocked))"
            debugLog.info("durum: \(summary, privacy: .public)")
        default:
            debugLog.error("bilinmeyen debug komutu: \(command, privacy: .public)")
        }
    }
}
#endif
