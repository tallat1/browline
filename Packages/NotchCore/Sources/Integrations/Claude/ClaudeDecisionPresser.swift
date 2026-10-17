import AppKit
import ApplicationServices

/// Karar kartındaki seçenek: Claude masaüstünde aynı kutunun aynı adlı düğmesine Erişilebilirlik ile basar, yanıt
/// kullanıcının kendi mesajı olarak gider. Claude var olan oturuma dışarıdan mesaj göndermeye izin vermediği için
/// tek yol bu; kutu Claude penceresinde görünür olmalı (çağıran önce oturumu açar).
///
/// Yanlış düğmeye basmamak için: yalnız `AXButton`, adı (⌘↩ işaretleri atılmış) seçenekle birebir aynı; kutunun
/// sorusunu ya da diğer seçenekleri içeren en yakın üst grupta bu adda tek düğme var; birden çok aday varsa basılmaz.
/// Electron erişilebilirlik ağacını yalnız istenince ve biraz gecikmeyle kurar (`AXManualAccessibility`, 2026-10-17
/// ölçümü: ilk sorguda 3 düğme, 1–3 sn sonra 75); iş bitince eski hâline döner.
public enum ClaudeDecisionPresser {
    public enum Outcome: Equatable, Sendable {
        case pressed
        case notTrusted
        case claudeNotRunning
        case notFound
        /// Birden çok uygun düğme: hangisi olduğu bilinmediği için basılmadı.
        case ambiguous
    }

    public static let bundleIdentifier = "com.anthropic.claudefordesktop"

    /// Arka planda çağrılmalı (AX çağrıları süreçler arası, ağaç birkaç yüz öğe). `attempts` boyunca yarım saniye
    /// arayla arar: oturum yeni açıldıysa kutu birazdan çizilir.
    public nonisolated static func press(label: String, ask: String?, options: [String], attempts: Int = 1) -> Outcome {
        guard AXIsProcessTrusted() else { return .notTrusted }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
            return .claudeNotRunning
        }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        let manual = "AXManualAccessibility" as CFString
        var previous: CFTypeRef?
        AXUIElementCopyAttributeValue(root, manual, &previous)
        let wasOn = (previous as? Bool) == true
        if !wasOn { AXUIElementSetAttributeValue(root, manual, kCFBooleanTrue) }
        defer { if !wasOn { AXUIElementSetAttributeValue(root, manual, kCFBooleanFalse) } }

        var outcome = Outcome.notFound
        for attempt in 0..<max(1, attempts) {
            if attempt > 0 { Thread.sleep(forTimeInterval: 0.5) }
            var windows: CFTypeRef?
            AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &windows)
            let trees = ((windows as? [AXUIElement]) ?? []).map { snapshot($0) }
            switch match(in: trees, label: label, ask: ask, options: options) {
            case .one(let node):
                guard let element = node.element else { return .notFound }
                // Değer AnyObject olarak tutuldu; AXUIElement bir CFType.
                let result = AXUIElementPerformAction(element as! AXUIElement, kAXPressAction as CFString)
                return result == .success ? .pressed : .notFound
            case .many:
                outcome = .ambiguous
            case .none:
                outcome = .notFound
            }
        }
        return outcome
    }

    // MARK: - Ağaç ve eşleştirme (test edilebilir)

    /// AX ağacının anlık görüntüsü: rol, görünen metinler, çocuklar.
    struct Node {
        var role: String
        var text: String
        var children: [Node] = []
        var element: AnyObject?
    }

    enum Match {
        case none
        case one(Node)
        case many
    }

    nonisolated static func snapshot(_ element: AXUIElement, depth: Int = 0) -> Node {
        func string(_ attribute: String) -> String {
            var value: CFTypeRef?
            AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
            return value as? String ?? ""
        }
        let role = string(kAXRoleAttribute)
        let text = [string(kAXTitleAttribute), string(kAXDescriptionAttribute), string(kAXValueAttribute)]
            .filter { !$0.isEmpty }.joined(separator: " ")
        var node = Node(role: role, text: text, element: element)
        guard depth < 80 else { return node }
        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        node.children = ((children as? [AXUIElement]) ?? []).map { snapshot($0, depth: depth + 1) }
        return node
    }

    /// Küçük harf, kısayol işaretleri ve Markdown imleri atılmış, boşluklar tek.
    nonisolated static func normalize(_ text: String) -> String {
        let dropped = text.lowercased().unicodeScalars.filter { !"⌘↩⏎⌥⇧⌃`*_".unicodeScalars.contains($0) }
        return String(String.UnicodeScalarView(dropped)).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Düğmenin adı: kendi metni yoksa çocuklarının metni (Electron çoğu düğmede metni çocuğa koyar).
    nonisolated static func fullText(_ node: Node) -> String {
        ([node.text] + node.children.map(fullText)).filter { !$0.isEmpty }.joined(separator: " ")
    }

    nonisolated static func match(in trees: [Node], label: String, ask: String?, options: [String]) -> Match {
        let target = normalize(label)
        let others = options.map(normalize).filter { $0 != target && !$0.isEmpty }
        // Sorunun ilk 60 karakteri yeter; Markdown kod bölütleri metni parçalasa da tam metin birleştirilip aranır.
        let anchor = ask.map { String(normalize($0).prefix(60)) }.flatMap { $0.isEmpty ? nil : $0 }
        guard !target.isEmpty, anchor != nil || !others.isEmpty else { return .none }

        var found: [Node] = []
        func isButton(_ node: Node, named name: String) -> Bool {
            node.role == "AXButton" && normalize(fullText(node)) == name
        }
        func buttons(in node: Node, named name: String) -> [Node] {
            (isButton(node, named: name) ? [node] : []) + node.children.flatMap { buttons(in: $0, named: name) }
        }
        func isBox(_ group: Node) -> Bool {
            let hasAsk = anchor.map { normalize(fullText(group)).contains($0) } ?? false
            return hasAsk || (!others.isEmpty && others.allSatisfy { !buttons(in: group, named: $0).isEmpty })
        }
        /// `path`: köke kadar üst gruplar (en yakın önce). Soruyu ya da diğer seçenekleri içeren EN YAKIN üst grup
        /// kutudur ve içinde bu adda tek düğme olmalı: daha yukarısı (sohbetin tamamı) eski bir mesajdaki aynı adlı
        /// düğmeyi de kapsar.
        func visit(_ node: Node, path: [Node]) {
            if isButton(node, named: target), let group = path.prefix(8).first(where: isBox),
               buttons(in: group, named: target).count == 1 {
                found.append(node)
            }
            for child in node.children { visit(child, path: [node] + path) }
        }
        for tree in trees { visit(tree, path: []) }
        switch found.count {
        case 0: return .none
        case 1: return .one(found[0])
        default: return .many
        }
    }
}
