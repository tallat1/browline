import ActivityAPI
import Foundation

// notch: Browline'a yerel soket üzerinden etkinlik gönderir. Kestirmeler "Kabuk Betiği Çalıştır"
// eylemiyle de çağrılabilir. Çıkış kodları: 0 tamam, 1 uygulama hatası, 2 kullanım, 3 uygulama çalışmıyor.
// Metinler dil sırasının ilkine göre Türkçe ya da İngilizce (APILanguage); uygulamanın yanıtları da öyle.

let language = APILanguage.current

let usage = language.text("""
Kullanım:
  notch push  --id ID --title METİN [--subtitle METİN] [--progress 0.4|40%] [--symbol hammer]
              [--tint #FF8800] [--priority 0-50] [--ttl SANİYE]
  notch end   --id ID
  notch flash --title METİN [--subtitle METİN] [--symbol checkmark.circle] [--tint #34C759] [--duration SANİYE]
  notch list
  notch ping
  notch ask   --id ID --title METİN [--subtitle METİN] [--detail METİN] [--symbol] [--tint] [--timeout SANİYE]
              Notch'ta İzin ver / Reddet sorusu; yanıtı yazar (allow | deny). Yanıt yoksa çıkış 4.
  notch claude-permission [--timeout SANİYE]
              Claude Code PermissionRequest kancası: stdin'deki isteği notch'ta sorar, kararı Claude'a
              yazar. Yanıt yoksa ya da uygulama kapalıysa hiçbir şey yazmaz (Claude kendi penceresini gösterir).

Örnek:
  notch push --id build --title "Derleme" --progress 40% --symbol hammer
  notch end --id build && notch flash --title "Derleme bitti" --symbol checkmark.circle

Çıkış kodları: 0 tamam, 1 uygulama hatası, 2 kullanım, 3 Browline çalışmıyor, 4 ask yanıtsız.
""", """
Usage:
  notch push  --id ID --title TEXT [--subtitle TEXT] [--progress 0.4|40%] [--symbol hammer]
              [--tint #FF8800] [--priority 0-50] [--ttl SECONDS]
  notch end   --id ID
  notch flash --title TEXT [--subtitle TEXT] [--symbol checkmark.circle] [--tint #34C759] [--duration SECONDS]
  notch list
  notch ping
  notch ask   --id ID --title TEXT [--subtitle TEXT] [--detail TEXT] [--symbol] [--tint] [--timeout SECONDS]
              Shows an Allow / Deny question in the notch and prints the answer (allow | deny).
              Exits with 4 if nobody answers.
  notch claude-permission [--timeout SECONDS]
              Claude Code PermissionRequest hook: asks the request from stdin in the notch and writes the
              decision for Claude. Writes nothing if there is no answer or the app isn't running (Claude then
              shows its own prompt).

Example:
  notch push --id build --title "Building" --progress 40% --symbol hammer
  notch end --id build && notch flash --title "Build passed" --symbol checkmark.circle

Exit codes: 0 ok, 1 app error, 2 usage, 3 Browline not running, 4 no answer to ask.
""")

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

/// Kanca kipi: Claude'u hiçbir koşulda bozmaz; her yolda çıkış 0, karar yoksa çıktı yok.
@MainActor
func runClaudePermission(timeout: TimeInterval) -> Never {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    guard let parsed = ClaudePermissionHook.parse(input) else { exit(0) }
    let request = ClaudePermissionHook.request(for: parsed, timeout: timeout, language: language)
    // Soket okuma süresi sorudan biraz uzun: soru notch'ta düşünce yanıt gelir.
    guard let response = try? ActivitySocketClient.send(request, timeout: timeout + 5), response.ok,
          let output = ClaudePermissionHook.output(for: response.decision, language: language) else { exit(0) }
    print(output)
    exit(0)
}

var arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first, !["-h", "--help", "help"].contains(command) else {
    print(usage)
    exit(arguments.isEmpty ? 2 : 0)
}
arguments.removeFirst()

if command == "claude-permission" {
    var timeout = ExternalQuestion.defaultTTL
    if arguments.count == 2, arguments[0] == "--timeout", let value = Double(arguments[1]),
       ExternalQuestion.ttlRange.contains(value) {
        timeout = value
    } else if !arguments.isEmpty {
        fail(language.text("Kullanım: notch claude-permission [--timeout 1-590]",
                           "Usage: notch claude-permission [--timeout 1-590]"), code: 2)
    }
    runClaudePermission(timeout: timeout)
}

var options: [String: String] = [:]
var index = 0
while index < arguments.count {
    let key = arguments[index]
    guard key.hasPrefix("--"), index + 1 < arguments.count else {
        fail(language.text("Beklenmeyen argüman: \(key)", "Unexpected argument: \(key)") + "\n\n\(usage)", code: 2)
    }
    options[String(key.dropFirst(2))] = arguments[index + 1]
    index += 2
}

@MainActor
func number(_ key: String) -> Double? {
    guard let raw = options[key] else { return nil }
    guard let value = ActivityRequest.number(from: raw) else {
        fail(language.text("--\(key) sayı olmalı: \(raw)", "--\(key) must be a number: \(raw)"), code: 2)
    }
    return value
}

@MainActor
func integer(_ key: String) -> Int? {
    guard let value = number(key) else { return nil }
    guard let integer = ActivityRequest.integer(from: value) else {
        let raw = options[key] ?? ""
        fail(language.text("--\(key) tam sayı olmalı: \(raw)", "--\(key) must be a whole number: \(raw)"), code: 2)
    }
    return integer
}

let operation: ActivityRequest.Operation
switch command {
case "push": operation = .push
case "end": operation = .end
case "flash": operation = .flash
case "list": operation = .list
case "ping": operation = .ping
case "ask": operation = .ask
default: fail(language.text("Bilinmeyen komut: \(command)", "Unknown command: \(command)") + "\n\n\(usage)", code: 2)
}

let known: Set<String> = ["id", "title", "subtitle", "progress", "symbol", "tint", "priority", "ttl", "duration",
                          "detail", "timeout"]
if let unknown = options.keys.first(where: { !known.contains($0) }) {
    fail(language.text("Bilinmeyen seçenek: --\(unknown)", "Unknown option: --\(unknown)"), code: 2)
}

let request = ActivityRequest(
    op: operation, id: options["id"], title: options["title"], subtitle: options["subtitle"],
    progress: number("progress"), symbol: options["symbol"], tint: options["tint"],
    priority: integer("priority"), ttl: number("timeout") ?? number("ttl"), duration: number("duration"),
    detail: options["detail"])

do {
    // ask kullanıcıyı bekler: okuma süresi soru süresinden biraz uzun.
    let waitTime = operation == .ask ? (request.ttl ?? ExternalQuestion.defaultTTL) + 5 : 3
    let response = try ActivitySocketClient.send(request, timeout: waitTime)
    guard response.ok else {
        fail("Browline: \(response.error ?? language.text("bilinmeyen hata", "unknown error"))", code: 1)
    }
    if operation == .ask {
        guard let decision = response.decision else { exit(4) }
        print(decision.rawValue)
    }
    if operation == .list {
        let activities = response.activities ?? []
        if activities.isEmpty { print(language.text("Etkin dış etkinlik yok", "No active activities")) }
        for activity in activities {
            let progress = activity.progress.map { value -> String in
                let percent = Int((value * 100).rounded())
                return language.text(" %\(percent)", " \(percent)%")
            } ?? ""
            let priority = language.text("öncelik \(activity.priority)", "priority \(activity.priority)")
            print("\(activity.id)\t\(activity.title)\(progress)\t\(priority)")
        }
    }
} catch {
    fail(error.description(in: language), code: error == .notRunning ? 3 : 1)
}
