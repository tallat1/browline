import ActivityAPI
import Foundation

// notch: NotchMVP'ye yerel soket üzerinden etkinlik gönderir. Kestirmeler "Kabuk Betiği Çalıştır"
// eylemiyle de çağrılabilir. Çıkış kodları: 0 tamam, 1 uygulama hatası, 2 kullanım, 3 uygulama çalışmıyor.

let usage = """
Kullanım:
  notch push  --id ID --title METİN [--subtitle METİN] [--progress 0.4|40%] [--symbol hammer]
              [--tint #FF8800] [--priority 0-50] [--ttl SANİYE]
  notch end   --id ID
  notch flash --title METİN [--subtitle METİN] [--symbol checkmark.circle] [--tint #34C759] [--duration SANİYE]
  notch list
  notch ping

Örnek:
  notch push --id build --title "Derleme" --progress 40% --symbol hammer
  notch end --id build && notch flash --title "Derleme bitti" --symbol checkmark.circle
"""

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

var arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first, !["-h", "--help", "help"].contains(command) else {
    print(usage)
    exit(arguments.isEmpty ? 2 : 0)
}
arguments.removeFirst()

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

let operation: ActivityRequest.Operation
switch command {
case "push": operation = .push
case "end": operation = .end
case "flash": operation = .flash
case "list": operation = .list
case "ping": operation = .ping
default: fail("Bilinmeyen komut: \(command)\n\n\(usage)", code: 2)
}

let known: Set<String> = ["id", "title", "subtitle", "progress", "symbol", "tint", "priority", "ttl", "duration"]
if let unknown = options.keys.first(where: { !known.contains($0) }) { fail("Bilinmeyen seçenek: --\(unknown)", code: 2) }

let request = ActivityRequest(
    op: operation, id: options["id"], title: options["title"], subtitle: options["subtitle"],
    progress: number("progress"), symbol: options["symbol"], tint: options["tint"],
    priority: number("priority").map { Int($0) }, ttl: number("ttl"), duration: number("duration"))

do {
    let response = try ActivitySocketClient.send(request)
    guard response.ok else { fail("NotchMVP: \(response.error ?? "bilinmeyen hata")", code: 1) }
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
