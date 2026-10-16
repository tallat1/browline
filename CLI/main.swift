import ActivityAPI
import Foundation

// notch: Browline'a yerel soket üzerinden etkinlik gönderir. Kestirmeler "Kabuk Betiği Çalıştır"
// eylemiyle de çağrılabilir. Çıkış kodları: 0 tamam, 1 uygulama hatası, 2 kullanım, 3 uygulama çalışmıyor.

let usage = """
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
"""

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

/// Kanca kipi: Claude'u hiçbir koşulda bozmaz; her yolda çıkış 0, karar yoksa çıktı yok.
func runClaudePermission(timeout: TimeInterval) -> Never {
    let turkish = Locale.preferredLanguages.first?.hasPrefix("tr") ?? false
    let input = FileHandle.standardInput.readDataToEndOfFile()
    guard let parsed = ClaudePermissionHook.parse(input) else { exit(0) }
    let request = ClaudePermissionHook.request(for: parsed, timeout: timeout, turkish: turkish)
    // Soket okuma süresi sorudan biraz uzun: soru notch'ta düşünce yanıt gelir.
    guard let response = try? ActivitySocketClient.send(request, timeout: timeout + 5), response.ok,
          let output = ClaudePermissionHook.output(for: response.decision, turkish: turkish) else { exit(0) }
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
        fail("Kullanım: notch claude-permission [--timeout 1-590]", code: 2)
    }
    runClaudePermission(timeout: timeout)
}

var options: [String: String] = [:]
var index = 0
while index < arguments.count {
    let key = arguments[index]
    guard key.hasPrefix("--"), index + 1 < arguments.count else { fail("Beklenmeyen argüman: \(key)\n\n\(usage)", code: 2) }
    options[String(key.dropFirst(2))] = arguments[index + 1]
    index += 2
}

@MainActor
func number(_ key: String) -> Double? {
    guard let raw = options[key] else { return nil }
    guard let value = ActivityRequest.number(from: raw) else { fail("--\(key) sayı olmalı: \(raw)", code: 2) }
    return value
}

@MainActor
func integer(_ key: String) -> Int? {
    guard let value = number(key) else { return nil }
    guard let integer = ActivityRequest.integer(from: value) else { fail("--\(key) tam sayı olmalı: \(options[key] ?? "")", code: 2) }
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
default: fail("Bilinmeyen komut: \(command)\n\n\(usage)", code: 2)
}

let known: Set<String> = ["id", "title", "subtitle", "progress", "symbol", "tint", "priority", "ttl", "duration",
                          "detail", "timeout"]
if let unknown = options.keys.first(where: { !known.contains($0) }) { fail("Bilinmeyen seçenek: --\(unknown)", code: 2) }

let request = ActivityRequest(
    op: operation, id: options["id"], title: options["title"], subtitle: options["subtitle"],
    progress: number("progress"), symbol: options["symbol"], tint: options["tint"],
    priority: integer("priority"), ttl: number("timeout") ?? number("ttl"), duration: number("duration"),
    detail: options["detail"])

do {
    // ask kullanıcıyı bekler: okuma süresi soru süresinden biraz uzun.
    let waitTime = operation == .ask ? (request.ttl ?? ExternalQuestion.defaultTTL) + 5 : 3
    let response = try ActivitySocketClient.send(request, timeout: waitTime)
    guard response.ok else { fail("Browline: \(response.error ?? "bilinmeyen hata")", code: 1) }
    if operation == .ask {
        guard let decision = response.decision else { exit(4) }
        print(decision.rawValue)
    }
    if operation == .list {
        let activities = response.activities ?? []
        if activities.isEmpty { print("Etkin dış etkinlik yok") }
        for activity in activities {
            let progress = activity.progress.map { " %\(Int(($0 * 100).rounded()))" } ?? ""
            print("\(activity.id)\t\(activity.title)\(progress)\töncelik \(activity.priority)")
        }
    }
} catch {
    fail(error.description, code: error == .notRunning ? 3 : 1)
}
