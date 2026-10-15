// MVP duman testi (debug derlemesi): notch'u debug komut kanalıyla açar, sekmeleri gezer ve
// her adımda YALNIZ panel penceresinin görüntüsünü alır. İmleci kullanmaz, altındaki
// pencereleri (kişisel içerik) yakalamaz. Gereken izin: betiği çalıştıran uygulamaya Ekran Kaydı.
//
// Kullanım: swift Scripts/smoke-test.swift [çıktı-klasörü]
import AppKit

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/smoke")
try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

func send(_ command: String) {
    DistributedNotificationCenter.default().postNotificationName(
        Notification.Name("com.talatozcoban.notchmvp.debug"), object: command, userInfo: nil,
        deliverImmediately: true)
}

/// Uygulamanın notch paneli: katman 27 (.mainMenu + 3).
func panelWindowIDs() -> [CGWindowID] {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return list.compactMap { window in
        guard window[kCGWindowOwnerName as String] as? String == "NotchMVP",
              window[kCGWindowLayer as String] as? Int == 27 else { return nil }
        return window[kCGWindowNumber as String] as? CGWindowID
    }
}

func capture(_ name: String) {
    for (index, id) in panelWindowIDs().enumerated() {
        let file = outputDirectory.appendingPathComponent(index == 0 ? "\(name).png" : "\(name)-\(index).png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-o", "-l", String(id), file.path]
        try? process.run()
        process.waitUntilExit()
        print("✓ \(file.lastPathComponent)")
    }
}

guard !panelWindowIDs().isEmpty else {
    print("NotchMVP paneli bulunamadı; uygulama açık mı?")
    exit(1)
}

send("close"); Thread.sleep(forTimeInterval: 0.8); capture("1-kapali")
send("flash:power"); Thread.sleep(forTimeInterval: 0.8); capture("2-kompakt-guc")
send("tab:media"); send("open"); Thread.sleep(forTimeInterval: 0.9); capture("3-acik-medya")
send("tab:calendar"); Thread.sleep(forTimeInterval: 0.5); capture("4-takvim")
send("tab:shelf"); Thread.sleep(forTimeInterval: 0.5); capture("5-raf")
send("tab:media"); send("close"); Thread.sleep(forTimeInterval: 3.5); capture("6-kapali-tekrar")

// Dış etkinlik API'si: uygulama paketindeki notch aracıyla.
let cli = "build/Build/Products/Debug/NotchMVP.app/Contents/Helpers/notch"
func notch(_ arguments: String...) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: cli)
    process.arguments = arguments
    try? process.run()
    process.waitUntilExit()
}
if FileManager.default.isExecutableFile(atPath: cli) {
    notch("push", "--id", "smoke", "--title", "Derleme", "--subtitle", "NotchMVP", "--progress", "40%",
          "--symbol", "hammer", "--tint", "#FF9F0A")
    Thread.sleep(forTimeInterval: 0.8); capture("7-kompakt-dis-etkinlik")
    send("tab:activities"); send("open"); Thread.sleep(forTimeInterval: 0.9); capture("8-acik-etkinlikler")
    send("close"); notch("end", "--id", "smoke")
    notch("flash", "--title", "Derleme bitti", "--symbol", "checkmark.circle.fill", "--tint", "#34C759")
    Thread.sleep(forTimeInterval: 0.8); capture("9-kisa-bildirim")
    send("tab:media")
}
