import Foundation

/// Claude plan limitlerini kullanıcının kurulu Claude Code'una sorar: `claude -p /usage`. Browline kimlik
/// bilgisine dokunmaz; komutu Claude Code kendi girişiyle yanıtlar ve model çağrısı yapmaz (2026-10-17
/// ölçümü: 2 sn, 0 token). Masaüstü uygulaması durum satırını çalıştırmadığı için yüzdelerin tek
/// kurallara uygun kaynağı bu. Çıktı düz metin: biçim değişirse `parse` nil döner ve kart "okunamadı" der.
public enum ClaudeUsageProbe {
    public enum Failure: Error, Equatable, Sendable {
        /// Bilinen yerlerde `claude` yok.
        case notInstalled
        /// Claude Code'da giriş yapılmamış.
        case signedOut
        /// Abonelik yerine API anahtarı kullanılıyor; plan limiti yok.
        case noSubscription
        /// Komut çalışmadı, zaman aşımına uğradı ya da çıktı anlaşılamadı.
        case unreadable
    }

    /// Kancalar kapalı (kullanıcının Claude kancaları notch'a sahte oturum düşürmesin), MCP sunucusu
    /// başlatılmaz, oturum kaydı yazılmaz.
    static let arguments = ["-p", "/usage", "--no-session-persistence", "--strict-mcp-config",
                            "--settings", #"{"disableAllHooks":true}"#]

    /// Arka planda çalışır (süreç başlatır, bekler). `workingDirectory` sabit tutulur: Claude Code her
    /// klasör için `~/.claude/projects` altında bir proje açar, her yoklamada yenisi birikmesin.
    public nonisolated static func fetch(workingDirectory: URL, now: Date = .now) -> Result<ClaudeUsageMonitor.Usage, Failure> {
        guard let executable = executable() else { return .failure(.notInstalled) }
        guard let text = run(executable, workingDirectory: workingDirectory) else { return .failure(.unreadable) }
        if let usage = parse(text, now: now) { return .success(usage) }
        return .failure(classify(text))
    }

    // MARK: - Claude Code'u bulma

    /// Kullanıcının kurduğu Claude Code önce; yoksa masaüstü uygulamasının kendi kopyası.
    nonisolated static func executable(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                                       fileManager: FileManager = .default) -> URL? {
        let candidates = [".local/bin/claude"].map { home.appendingPathComponent($0) }
            + ["/opt/homebrew/bin/claude", "/usr/local/bin/claude"].map { URL(fileURLWithPath: $0) }
            + [".claude/local/claude", ".npm-global/bin/claude", ".bun/bin/claude", ".volta/bin/claude"]
                .map { home.appendingPathComponent($0) }
            + desktopBundled(home: home, fileManager: fileManager)
        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    /// Claude masaüstü: `claude-code/<sürüm>/<özet>/claude.app/Contents/MacOS/claude`, en yeni sürüm önce.
    /// Bu yerleşim belgelenmemiş; değişirse aday listesinden sessizce düşer.
    nonisolated static func desktopBundled(home: URL, fileManager: FileManager) -> [URL] {
        let root = home.appendingPathComponent("Library/Application Support/Claude/claude-code", isDirectory: true)
        let versions = ((try? fileManager.contentsOfDirectory(atPath: root.path)) ?? [])
            .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
        return versions.flatMap { version in
            let directory = root.appendingPathComponent(version, isDirectory: true)
            return ((try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []).map {
                directory.appendingPathComponent($0).appendingPathComponent("claude.app/Contents/MacOS/claude")
            }
        }
    }

    // MARK: - Çalıştırma

    nonisolated private static func run(_ executable: URL, workingDirectory: URL) -> String? {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        // Çıktı dosyaya: Claude Code'un yan süreçleri boruyu açık tutsa da okuma takılmaz.
        let outputURL = fileManager.temporaryDirectory.appendingPathComponent("browline-claude-usage-\(UUID().uuidString).txt")
        guard fileManager.createFile(atPath: outputURL.path, contents: nil),
              let output = try? FileHandle(forWritingTo: outputURL) else { return nil }
        defer { try? fileManager.removeItem(at: outputURL) }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        var environment = ProcessInfo.processInfo.environment
        // Browline bir Claude oturumundan başlatıldıysa iç içe oturum sanılmasın.
        environment["CLAUDECODE"] = nil
        environment["CLAUDE_CODE_ENTRYPOINT"] = nil
        // Arka plan yoklaması güncelleme indirmesin, telemetri ve hata raporu göndermesin.
        environment["DISABLE_AUTOUPDATER"] = "1"
        environment["DISABLE_TELEMETRY"] = "1"
        environment["DISABLE_ERROR_REPORTING"] = "1"
        environment["NO_COLOR"] = "1"
        // GUI uygulamasında PATH kısa; npm ile kurulan claude node'u bulabilsin.
        environment["PATH"] = [executable.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
            .joined(separator: ":")
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch {
            try? output.close()
            Log.integrations.error("Claude /usage başlatılamadı: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 30, execute: watchdog)
        process.waitUntilExit()
        watchdog.cancel()
        try? output.close()
        let text = try? String(contentsOf: outputURL, encoding: .utf8)
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            Log.integrations.error("Claude /usage çıkış \(process.terminationStatus)")
            // Giriş yapılmamışsa da sıfırdan farklı çıkabilir; metin sınıflandırmaya gider.
            return text?.isEmpty == false ? text : nil
        }
        return text
    }

    // MARK: - Çözümleme

    /// "Current session: 29% used · resets Oct 17 at 10:09pm (Europe/Istanbul)" ve
    /// "Current week (all models): 34% used · resets Oct 20 at 12pm (Europe/Istanbul)". Model başına haftalık
    /// satırlar ("Current week (Opus)") atlanır. İki pencere de yoksa nil.
    nonisolated static func parse(_ text: String, now: Date) -> ClaudeUsageMonitor.Usage? {
        var fiveHour: ClaudeUsageMonitor.Window?
        var sevenDay: ClaudeUsageMonitor.Window?
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let lower = line.lowercased()
            if lower.hasPrefix("current session") {
                fiveHour = fiveHour ?? window(from: line, now: now)
            } else if lower.hasPrefix("current week:") || lower.hasPrefix("current week (all models)") {
                sevenDay = sevenDay ?? window(from: line, now: now)
            }
        }
        guard fiveHour != nil || sevenDay != nil else { return nil }
        return .init(fiveHour: fiveHour, sevenDay: sevenDay, capturedAt: now, source: .claudeCode)
    }

    nonisolated static func window(from line: String, now: Date) -> ClaudeUsageMonitor.Window? {
        guard let match = line.firstMatch(of: #/(\d+(?:\.\d+)?)\s*%\s*used/#.ignoresCase()),
              let used = Double(match.1) else { return nil }
        let reset = line.firstMatch(of: #/resets\s+(.+)$/#.ignoresCase()).flatMap { resetDate(String($0.1), now: now) }
        return .init(usedPercentage: min(max(used, 0), 100), resetsAt: reset)
    }

    nonisolated private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    /// "Oct 17 at 10:09pm (Europe/Istanbul)", "Oct 20 at 12pm", "10pm". Yıl yazılmaz: bir günden eski görünen
    /// tarih gelecek yıla (Aralık → Ocak), yalnız saat verilmişse geçmiş saat yarına sayılır.
    nonisolated static func resetDate(_ text: String, now: Date) -> Date? {
        var text = text.trimmingCharacters(in: .whitespaces)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        if let zone = text.firstMatch(of: #/\s*\(([^)]+)\)\s*$/#) {
            if let parsed = TimeZone(identifier: String(zone.1)) { calendar.timeZone = parsed }
            text.removeSubrange(zone.range)
        }
        guard let match = text.wholeMatch(
            of: #/(?:([a-z]{3})[a-z]*\.?\s+(\d{1,2}),?(?:\s+at)?\s*)?(?:(\d{1,2})(?::(\d{2}))?\s*([ap])\.?m\.?)?/#.ignoresCase()),
            match.1 != nil || match.3 != nil else { return nil }
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = 0
        components.minute = 0
        if let hour = match.3.flatMap({ Int($0) }), (1...12).contains(hour) {
            components.hour = hour % 12 + (match.5?.lowercased() == "p" ? 12 : 0)
            components.minute = match.4.flatMap { Int($0) } ?? 0
        } else if match.3 != nil {
            return nil
        }
        if let name = match.1 {
            guard let month = months.firstIndex(of: name.lowercased()), let day = match.2.flatMap({ Int($0) }) else { return nil }
            components.month = month + 1
            components.day = day
            guard let date = calendar.date(from: components) else { return nil }
            guard date < now.addingTimeInterval(-86_400), let year = components.year else { return date }
            components.year = year + 1
            return calendar.date(from: components)
        }
        guard let date = calendar.date(from: components) else { return nil }
        return date < now ? calendar.date(byAdding: .day, value: 1, to: date) : date
    }

    /// Limit satırı yoksa neden: giriş yok, API anahtarı ya da anlaşılmayan çıktı.
    nonisolated static func classify(_ text: String) -> Failure {
        let lower = text.lowercased()
        if lower.contains("/login") || lower.contains("not logged in") || lower.contains("log in") { return .signedOut }
        if lower.contains("api key") || lower.contains("api usage billing") { return .noSubscription }
        return .unreadable
    }
}
