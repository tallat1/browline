import CoreAudio
import Foundation
import Testing
@testable import Integrations

struct TrackChangeTests {
    let first = NowPlayingInfo(title: "A", artist: "X", playbackRate: 1, isPlaying: true)

    @Test func newTitleOrArtistIsChange() {
        var next = first
        next.title = "B"
        #expect(NowPlayingInfo.isTrackChange(from: first, to: next))
        next = first
        next.artist = "Y"
        #expect(NowPlayingInfo.isTrackChange(from: first, to: next))
    }

    @Test func pauseSeekAndFirstAppearanceAreNot() {
        var paused = first
        paused.isPlaying = false
        paused.title = "B"
        #expect(!NowPlayingInfo.isTrackChange(from: first, to: paused))
        var moved = first
        moved.elapsedTime = 42
        #expect(!NowPlayingInfo.isTrackChange(from: first, to: moved))
        #expect(!NowPlayingInfo.isTrackChange(from: nil, to: first))
    }
}

struct AudioOutputTests {
    @Test func symbolsFromNameThenTransport() {
        typealias Monitor = AudioOutputMonitor
        #expect(Monitor.symbolName(for: .init(id: 1, name: "Talat’s AirPods Pro", transport: .bluetooth)) == "airpodspro")
        #expect(Monitor.symbolName(for: .init(id: 1, name: "AirPods Max", transport: .bluetooth)) == "airpodsmax")
        #expect(Monitor.symbolName(for: .init(id: 1, name: "WH-1000XM5", transport: .bluetooth)) == "headphones")
        #expect(Monitor.symbolName(for: .init(id: 1, name: "MacBook Pro Hoparlörü", transport: .builtIn)) == "laptopcomputer")
        #expect(Monitor.symbolName(for: .init(id: 1, name: "LG", transport: .display)) == "tv")
    }

    @Test func transportMapping() {
        #expect(AudioOutputMonitor.transport(rawValue: kAudioDeviceTransportTypeBluetoothLE) == .bluetooth)
        #expect(AudioOutputMonitor.transport(rawValue: kAudioDeviceTransportTypeBuiltIn) == .builtIn)
        #expect(AudioOutputMonitor.transport(rawValue: kAudioDeviceTransportTypeVirtual) == .other)
    }
}

@MainActor
struct CountdownTimerTests {
    @Test func remainingProgressAndAdd() {
        let timer = CountdownTimer()
        let start = Date(timeIntervalSince1970: 1000)
        timer.start(seconds: 60, now: start)
        #expect(timer.remaining(at: start.addingTimeInterval(15)) == 45)
        #expect(timer.progress(at: start.addingTimeInterval(15)) == 0.25)
        timer.add(seconds: 60, now: start.addingTimeInterval(15))
        #expect(timer.remaining(at: start.addingTimeInterval(15)) == 105)
        #expect(timer.duration == 120)
        timer.cancel()
        #expect(!timer.isRunning)
    }

    @Test func finishesAndNotifies() async throws {
        let timer = CountdownTimer()
        var finished = false
        timer.onFinished = { finished = true }
        timer.start(seconds: 1)
        try await Task.sleep(for: .milliseconds(1300))
        #expect(finished)
        #expect(!timer.isRunning)
    }

    @Test func formatting() {
        #expect(CountdownTimer.format(65) == "1:05")
        #expect(CountdownTimer.format(0.2) == "0:01")
        #expect(CountdownTimer.format(3725) == "1:02:05")
    }
}

@MainActor
struct KeepAwakeTests {
    /// Gerçek güç iddiası kurulur ve hemen bırakılır; sistemde iz kalmaz.
    @Test func startAndStopReleasesAssertion() {
        let awake = KeepAwake()
        #expect(awake.start(for: .seconds(30), reason: "NotchMVP test"))
        #expect(awake.isActive)
        #expect(awake.endsAt != nil)
        awake.stop()
        #expect(!awake.isActive)
        #expect(awake.endsAt == nil)
    }
}

struct BatteryAlertTests {
    func state(_ percent: Int, plugged: Bool = false) -> BatteryMonitor.State {
        BatteryMonitor.State(percent: percent, isCharging: plugged && percent < 100, isPluggedIn: plugged)
    }

    @Test func lowAlertsOnlyWhenCrossingDown() {
        #expect(BatteryMonitor.alert(from: state(21), to: state(20)) == .low(percent: 20))
        #expect(BatteryMonitor.alert(from: state(11), to: state(10)) == .low(percent: 10))
        #expect(BatteryMonitor.alert(from: state(20), to: state(19)) == nil)
        #expect(BatteryMonitor.alert(from: state(21, plugged: true), to: state(20, plugged: true)) == nil)
        #expect(BatteryMonitor.alert(from: nil, to: state(5)) == nil)
    }

    @Test func fullWhenReachingHundredOnPower() {
        #expect(BatteryMonitor.alert(from: state(99, plugged: true), to: state(100, plugged: true)) == .full)
        #expect(BatteryMonitor.alert(from: state(100, plugged: true), to: state(100, plugged: true)) == nil)
    }
}

struct SystemStatsTests {
    @Test func cpuUsageBetweenSamples() {
        let first = SystemStats.CPUTicks(busy: 100, total: 1000)
        #expect(SystemStats.cpuUsage(from: first, to: .init(busy: 150, total: 1100)) == 0.5)
        #expect(SystemStats.cpuUsage(from: nil, to: first) == nil)
        #expect(SystemStats.cpuUsage(from: first, to: first) == nil)
    }
}

struct PomodoroTests {
    @Test func cycleWithLongBreakEveryFourthRound() {
        var phase = Pomodoro.first
        var seen: [Pomodoro.Phase] = [phase]
        for _ in 0..<8 {
            phase = Pomodoro.next(after: phase)
            seen.append(phase)
        }
        #expect(seen == [.focus(round: 1), .shortBreak(afterRound: 1), .focus(round: 2), .shortBreak(afterRound: 2),
                         .focus(round: 3), .shortBreak(afterRound: 3), .focus(round: 4), .longBreak(afterRound: 4),
                         .focus(round: 5)])
        #expect(Pomodoro.duration(of: .longBreak(afterRound: 4)) == 15 * 60)
        #expect(Pomodoro.Phase.shortBreak(afterRound: 1).isBreak)
    }
}

struct WeatherTests {
    @Test func parsesForecastAndPlace() throws {
        let forecast = Data("""
        {"current":{"time":"2026-10-16T00:30","interval":900,"temperature_2m":12.5,"weather_code":80,"is_day":0},
         "daily":{"time":["2026-10-16"],"temperature_2m_max":[12.5],"temperature_2m_min":[8.7]}}
        """.utf8)
        let conditions = try WeatherMonitor.parseForecast(forecast)
        #expect(conditions == .init(temperature: 12.5, code: 80, isDay: false, high: 12.5, low: 8.7))
        let place = Data(#"{"results":[{"name":"Ankara","latitude":39.92,"longitude":32.85,"country":"Türkiye"}]}"#.utf8)
        #expect(try WeatherMonitor.parsePlace(place) == .init(name: "Ankara", latitude: 39.92, longitude: 32.85, country: "Türkiye"))
        #expect(try WeatherMonitor.parsePlace(Data(#"{"generationtime_ms":0.1}"#.utf8)) == nil)
        #expect(throws: WeatherMonitor.WeatherError.badResponse) { try WeatherMonitor.parseForecast(Data("{}".utf8)) }
    }

    @Test func symbols() {
        #expect(WeatherMonitor.symbolName(code: 0, isDay: true) == "sun.max.fill")
        #expect(WeatherMonitor.symbolName(code: 0, isDay: false) == "moon.stars.fill")
        #expect(WeatherMonitor.symbolName(code: 81, isDay: true) == "cloud.heavyrain.fill")
        #expect(WeatherMonitor.symbolName(code: 96, isDay: true) == "cloud.bolt.rain.fill")
    }
}

@MainActor
struct NotesStoreTests {
    @Test func persistsOnFlushAndReloads() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NotesStore(directory: directory)
        #expect(store.text.isEmpty)
        store.text = "süt al\nPR'a bak"
        store.flush()
        #expect(NotesStore(directory: directory).text == "süt al\nPR'a bak")
    }
}

struct ClaudeUsageTests {
    @Test func parsesScriptFormatAndStatuslineFormat() throws {
        let script = Data(#"{"captured_at":1760000000,"five_hour":{"used_percentage":42.4,"resets_at":1760007200},"seven_day":{"used_percentage":18}}"#.utf8)
        let usage = try #require(ClaudeUsageMonitor.parse(script, fallbackCapturedAt: .distantPast))
        #expect(usage.fiveHour == .init(usedPercentage: 42.4, resetsAt: Date(timeIntervalSince1970: 1760007200)))
        #expect(usage.sevenDay == .init(usedPercentage: 18, resetsAt: nil))
        #expect(usage.capturedAt == Date(timeIntervalSince1970: 1760000000))

        let statusline = Data(#"{"session_id":"x","rate_limits":{"seven_day":{"used_percentage":41.2,"resets_at":1738857600}}}"#.utf8)
        let fallback = Date(timeIntervalSince1970: 5)
        let second = try #require(ClaudeUsageMonitor.parse(statusline, fallbackCapturedAt: fallback))
        #expect(second.fiveHour == nil)
        #expect(second.sevenDay?.usedPercentage == 41.2)
        #expect(second.capturedAt == fallback)
        #expect(ClaudeUsageMonitor.parse(Data(#"{"session_id":"x"}"#.utf8), fallbackCapturedAt: fallback) == nil)
    }

    @Test func alertsOnlyWhenCrossingUp() {
        #expect(ClaudeUsageMonitor.crossedThreshold(from: 79, to: 81) == 80)
        #expect(ClaudeUsageMonitor.crossedThreshold(from: 70, to: 96) == 95)
        #expect(ClaudeUsageMonitor.crossedThreshold(from: 85, to: 90) == nil)
        #expect(ClaudeUsageMonitor.crossedThreshold(from: nil, to: 99) == nil)
    }
}

struct ClaudeAccountTests {
    @Test func parsesProfileWithoutSecrets() throws {
        let data = Data(#"{"userID":"x","oauthAccount":{"emailAddress":"ada@example.com","displayName":"Ada","organizationName":"Örnek AŞ","organizationType":"claude_max","organizationRateLimitTier":"default_claude_max_20x","profileFetchedAt":1760000000000}}"#.utf8)
        let account = try #require(ClaudeAccount.parse(data))
        #expect(account.email == "ada@example.com")
        #expect(account.displayName == "Ada")
        #expect(account.organizationName == "Örnek AŞ")
        #expect(account.plan == "Max 20x")
        #expect(account.fetchedAt == Date(timeIntervalSince1970: 1760000000))
        #expect(ClaudeAccount.parse(Data(#"{"userID":"x"}"#.utf8)) == nil)
        let personal = Data(#"{"oauthAccount":{"emailAddress":"ada@example.com","organizationName":"ada@example.com's Organization"}}"#.utf8)
        #expect(try #require(ClaudeAccount.parse(personal)).organizationName == nil)
    }

    @Test func planNames() {
        #expect(ClaudeAccount.planName(type: "claude_max", tier: "default_claude_max_5x") == "Max 5x")
        #expect(ClaudeAccount.planName(type: "claude_pro", tier: nil) == "Pro")
        #expect(ClaudeAccount.planName(type: "claude_team", tier: nil) == "Team")
        #expect(ClaudeAccount.planName(type: "something_else", tier: nil) == nil)
    }
}

struct ClaudeLimitLogTests {
    @Test func parsesRejectedLimitLines() throws {
        let line = #"{"type":"assistant","timestamp":"2026-10-08T23:18:33.004Z","apiErrorParams":{"rate_limit_info":{"status":"rejected","resetsAt":1791511800,"rateLimitType":"five_hour","overageStatus":"rejected","isUsingOverage":false}}}"#
        let hit = try #require(ClaudeLimitLog.parse(line: line))
        #expect(hit.type == "five_hour")
        #expect(hit.resetsAt == Date(timeIntervalSince1970: 1791511800))
        #expect(hit.hitAt != nil)
        #expect(!hit.isWeekly)
        let quota = #"{"quotaLimits":{"status":"rejected","resetsAt":1790847000,"rateLimitType":"seven_day_opus"}}"#
        let weekly = try #require(ClaudeLimitLog.parse(line: quota))
        #expect(weekly.isWeekly)
        #expect(weekly.modelSuffix == "Opus")
        #expect(ClaudeLimitLog.parse(line: #"{"quotaLimits":{"status":"allowed","resetsAt":1,"rateLimitType":"five_hour"}}"#) == nil)
    }

    @Test func activeHitsOnlyFutureAndLatestPerType() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("p"), withIntermediateDirectories: true)
        // Dosyanın değişme zamanı gerçek saat; "şimdi" de ona göre (7 günlük pencere).
        let now = Date(timeIntervalSince1970: Date.now.timeIntervalSince1970.rounded(.down))
        let base = Int(now.timeIntervalSince1970)
        func line(_ type: String, _ offset: Int) -> String {
            #"{"apiErrorParams":{"rate_limit_info":{"status":"rejected","resetsAt":\#(base + offset),"rateLimitType":"\#(type)"}}}"#
        }
        let content = [line("five_hour", -1_000), line("five_hour", 3_600),
                       line("five_hour", 1_000), line("seven_day", 300_000), #"{"type":"user"}"#]
            .joined(separator: "\n")
        try content.write(to: directory.appendingPathComponent("p/a.jsonl"), atomically: true, encoding: .utf8)
        let hits = ClaudeLimitLog(directory: directory).activeHits(now: now)
        #expect(hits.map(\.type) == ["seven_day", "five_hour"])
        #expect(hits.last?.resetsAt == Date(timeIntervalSince1970: TimeInterval(base + 3_600)))
    }
}

/// Uç nokta biçimi topluluk raporlarından; sahte veriyle. Gerçek anahtar testlere hiç girmez.
struct ClaudeUsageAPITests {
    @Test func parsesUtilizationAndMicrosecondResets() throws {
        let body = Data(#"{"five_hour":{"utilization":23.0,"resets_at":"2026-10-16T04:59:59.943648+00:00"},"seven_day":{"utilization":41.5,"resets_at":"2026-10-20T08:00:00+00:00"},"seven_day_opus":null}"#.utf8)
        let captured = Date(timeIntervalSince1970: 1_800_000_000)
        let usage = try #require(ClaudeUsageAPI.parse(body, capturedAt: captured))
        #expect(usage.fiveHour?.usedPercentage == 23)
        #expect(usage.sevenDay?.usedPercentage == 41.5)
        #expect(usage.fiveHour?.resetsAt == ClaudeUsageAPI.date(from: "2026-10-16T04:59:59+00:00"))
        #expect(usage.capturedAt == captured)
        #expect(ClaudeUsageAPI.parse(Data(#"{"error":"x"}"#.utf8), capturedAt: captured) == nil)
    }

    @Test func dates() {
        #expect(ClaudeUsageAPI.date(from: "2026-10-16T04:59:59Z") == Date(timeIntervalSince1970: 1_792_126_799))
        #expect(ClaudeUsageAPI.date(from: "2026-10-16T04:59:59.5Z") == Date(timeIntervalSince1970: 1_792_126_799))
        #expect(ClaudeUsageAPI.date(from: "dün") == nil)
    }

    @Test func credentialsNeedAccessTokenOnly() throws {
        let fake = Data(#"{"claudeAiOauth":{"accessToken":"sahte-anahtar","refreshToken":"sahte-yenileme","expiresAt":1800000000000}}"#.utf8)
        let credentials = try #require(ClaudeUsageAPI.parseCredentials(fake))
        #expect(credentials.accessToken == "sahte-anahtar")
        #expect(credentials.expiresAt == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(ClaudeUsageAPI.parseCredentials(Data(#"{"claudeAiOauth":{}}"#.utf8)) == nil)
    }
}

struct ShelfActionTests {
    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("notch-raf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func singleItemZipGoesNextToOriginal() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("rapor.txt")
        try "merhaba".write(to: file, atomically: true, encoding: .utf8)
        let destination = ShelfStore.archiveURL(for: [file], downloads: folder, now: .now)
        #expect(destination == folder.appendingPathComponent("rapor.txt.zip"))
        let result = try #require(ShelfStore.runCompression([file], to: destination))
        #expect(FileManager.default.fileExists(atPath: result.path))
        // Var olan adla çakışınca numaralanır.
        #expect(ShelfStore.archiveURL(for: [file], downloads: folder, now: .now).lastPathComponent == "rapor.txt 2.zip")
    }

    @Test func multipleItemsBecomeOneArchive() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = folder.appendingPathComponent("a.txt")
        let second = folder.appendingPathComponent("b.txt")
        try "a".write(to: first, atomically: true, encoding: .utf8)
        try "b".write(to: second, atomically: true, encoding: .utf8)
        let destination = ShelfStore.archiveURL(for: [first, second], downloads: folder, now: Date(timeIntervalSince1970: 0))
        #expect(destination.lastPathComponent.hasPrefix("Arşiv "))
        let result = try #require(ShelfStore.runCompression([first, second], to: destination))
        let listing = Process()
        listing.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo")
        listing.arguments = ["-1", result.path]
        let pipe = Pipe()
        listing.standardOutput = pipe
        try listing.run()
        listing.waitUntilExit()
        let names = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(names.contains("a.txt"))
        #expect(names.contains("b.txt"))
    }
}

@MainActor
struct BluetoothMonitorTests {
    // system_profiler -json çıktısının özü (2026-10-16, macOS 27, Türkçe bölge: "%80").
    static let sample = #"{"SPBluetoothDataType":[{"device_connected":[{"Talat (AirPods Pro)":{"device_batteryLevelCase":"%15","device_batteryLevelLeft":"%80","device_batteryLevelRight":"%79","device_minorType":"Headphones"}},{"Talat (AirPods Pro)":{"device_batteryLevelCase":"%15"}},{"Magic Keyboard":{"device_batteryLevelMain":"18%","device_minorType":"Keyboard"}}],"device_not_connected":[{"Eski":{}}]}]}"#

    @Test func parsesAndMergesDevices() {
        let devices = BluetoothMonitor.parse(Data(Self.sample.utf8))
        #expect(devices.map(\.name) == ["Talat (AirPods Pro)", "Magic Keyboard"])
        #expect(devices[0].kind == .headphones)
        #expect(devices[0].left == 80)
        #expect(devices[0].right == 79)
        #expect(devices[0].caseLevel == 15)
        #expect(devices[0].lowest == 79)  // kutu hariç
        #expect(devices[1].kind == .keyboard)
        #expect(devices[1].main == 18)
    }

    @Test func shortNameDropsOwner() {
        func short(_ name: String) -> String { BluetoothMonitor.Device(name: name, kind: .other).shortName }
        #expect(short("Talat (AirPods Pro)") == "AirPods Pro")
        #expect(short("Talat’s Magic Keyboard") == "Magic Keyboard")
        #expect(short("MX Master 3") == "MX Master 3")
        #expect(short("(Boş)") == "(Boş)")
    }

    @Test func connectDisconnectAndLowBatteryOnce() {
        let monitor = BluetoothMonitor()
        var connected: [String] = [], disconnected: [String] = [], low: [String] = []
        monitor.onConnected = { connected.append($0.name) }
        monitor.onDisconnected = { disconnected.append($0.name) }
        monitor.onLowBattery = { device, level in low.append("\(device.name) \(level)") }
        let keyboard = BluetoothMonitor.Device(name: "Klavye", kind: .keyboard, main: 50)
        monitor.apply([keyboard])  // ilk okuma: bağlandı sayılmaz
        #expect(connected.isEmpty)
        let mouse = BluetoothMonitor.Device(name: "Fare", kind: .mouse, main: 18)
        monitor.apply([keyboard, mouse])
        monitor.apply([keyboard, mouse])  // aynı eşik ikinci kez uyarılmaz
        #expect(connected == ["Fare"])
        #expect(low == ["Fare 18"])
        var drained = mouse
        drained.main = 9
        monitor.apply([keyboard, drained])
        #expect(low == ["Fare 18", "Fare 9"])
        monitor.apply([keyboard])
        #expect(disconnected == ["Fare"])
    }
}

struct SpectrumAnalyzerTests {
    static func sine(_ frequency: Double, seconds: Double = 0.5, rate: Double = 48_000, amplitude: Float = 0.3) -> [Float] {
        (0..<Int(seconds * rate)).map { amplitude * Float(sin(2 * .pi * frequency * Double($0) / rate)) }
    }

    @Test func bassToneLightsFirstBand() {
        let levels = SpectrumLevels()
        let analyzer = SpectrumAnalyzer(sampleRate: 48_000, output: levels)
        analyzer.consume(mono: Self.sine(80))
        let result = levels.read()
        #expect(result.hasSignal)
        #expect(result.values[0] > 0.8)
        #expect(result.values[3] < result.values[0])
    }

    @Test func trebleToneLightsLastBand() {
        let levels = SpectrumLevels()
        let analyzer = SpectrumAnalyzer(sampleRate: 44_100, output: levels)
        // Önce bas: tepeler oturur; sonra tiz, bas bandı iner.
        analyzer.consume(mono: Self.sine(80, rate: 44_100))
        analyzer.consume(mono: Self.sine(5_000, rate: 44_100))
        let result = levels.read()
        #expect(result.values[3] > 0.8)
        #expect(result.values[0] < 0.5)
    }

    /// 6 dB'lik vuruşlar (müzikte tipik) çubuğu belirgin oynatmalı; 30 dB aralıkta tepede kalıyordu.
    @Test func sixDecibelBeatsSwingTheBar() {
        let levels = SpectrumLevels()
        let analyzer = SpectrumAnalyzer(sampleRate: 48_000, output: levels)
        let rate = 48_000.0
        let signal: [Float] = (0..<Int(3 * rate)).map { index in
            let time = Double(index) / rate
            let loud = Int(time / 0.25) % 2 == 0
            return (loud ? 0.3 : 0.15) * Float(sin(2 * .pi * 80 * time))
        }
        var observed: [Float] = []
        for start in stride(from: 0, to: signal.count, by: SpectrumAnalyzer.fftSize) {
            analyzer.consume(mono: Array(signal[start..<min(signal.count, start + SpectrumAnalyzer.fftSize)]))
            if start > signal.count / 2 { observed.append(levels.read().values[0]) }
        }
        let swing = (observed.max() ?? 0) - (observed.min() ?? 0)
        #expect(swing > 0.4, "salınım \(swing)")
    }

    @Test func silenceIsNoSignal() {
        let levels = SpectrumLevels()
        let analyzer = SpectrumAnalyzer(sampleRate: 48_000, output: levels)
        analyzer.consume(mono: [Float](repeating: 0, count: 4_096))
        #expect(!levels.read().hasSignal)
        #expect(levels.read().values.allSatisfy { $0 == 0 })
    }

    @Test func bandsCoverAudibleRange() {
        let bins = SpectrumAnalyzer.binRanges(sampleRate: 48_000)
        #expect(bins.count == SpectrumLevels.bandCount)
        #expect(zip(bins, bins.dropFirst()).allSatisfy { $0.upperBound == $1.lowerBound })
        #expect(bins.allSatisfy { !$0.isEmpty })
    }
}
