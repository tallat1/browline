import AppKit
import ApplicationServices

/// Karar kartındaki seçenek: Claude masaüstünde aynı kutunun aynı adlı düğmesine Erişilebilirlik ile basar, yanıt
/// kullanıcının kendi mesajı olarak gider. Claude var olan oturuma dışarıdan mesaj göndermeye izin vermediği için
/// tek yol bu; kutu Claude penceresinde görünür olmalı (çağıran önce oturumu açar).
///
/// Yanlış düğmeye basmamak için: yalnız `AXButton`; başlığı, açıklaması ya da içindeki metin (her biri AYRI; Electron
/// adı hem düğmeye hem çocuk metne koyar, birleşince iki kez geçer) seçenekle birebir aynı, sondaki kısayol ipucu
/// (⌘↵, "Enter") hariç; kutunun sorusunu ya da diğer seçenekleri içeren en yakın üst grupta bu adda tek düğme var;
/// birden çok aday varsa basılmaz. Electron erişilebilirlik ağacını yalnız istenince ve gecikmeyle kurar
/// (`AXManualAccessibility`, 2026-10-17 ölçümü: ilk sorguda 3 düğme, 1–3 sn sonra 75): uygulama kart görününce
/// `setTreeEnabled(true)` ile önceden açar, kart kalkınca eski hâline döndürür.
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

    /// Arka planda çağrılmalı (AX çağrıları süreçler arası, ağaç birkaç yüz öğe). Yarım saniye arayla `firstAttempts`
    /// kez arar; bulamazsa `beforeRetry` (ör. oturumu açmak) çağrılır ve `retryAttempts` kez daha aranır.
    /// `pid`: oturumun sahibi olan Claude örneği (birden çok hesap aynı anda açık olabilir); nil ise hepsinde aranır
    /// ve tümünde tek eşleşme olmalı.
    public nonisolated static func press(label: String, ask: String?, options: [String], pid: pid_t? = nil, firstAttempts: Int = 1,
                                         retryAttempts: Int = 0, beforeRetry: (@Sendable () -> Void)? = nil) -> Outcome {
        guard AXIsProcessTrusted() else { return .notTrusted }
        let roots = applications(pid).map { AXUIElementCreateApplication($0) }
        guard !roots.isEmpty else { return .claudeNotRunning }
        let manual = "AXManualAccessibility" as CFString
        let wasOn = roots.map { root -> Bool in
            var previous: CFTypeRef?
            AXUIElementCopyAttributeValue(root, manual, &previous)
            return (previous as? Bool) == true
        }
        for (root, on) in zip(roots, wasOn) where !on { AXUIElementSetAttributeValue(root, manual, kCFBooleanTrue) }
        defer { for (root, on) in zip(roots, wasOn) where !on { AXUIElementSetAttributeValue(root, manual, kCFBooleanFalse) } }

        var outcome = Outcome.notFound
        let first = max(1, firstAttempts)
        for attempt in 0..<(first + max(0, retryAttempts)) {
            if attempt == first, outcome == .notFound { beforeRetry?() }
            if attempt > 0 { Thread.sleep(forTimeInterval: 0.5) }
            let trees = roots.flatMap { root -> [Node] in
                var windows: CFTypeRef?
                AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &windows)
                return ((windows as? [AXUIElement]) ?? []).map { snapshot($0) }
            }
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

    /// Verilen örnek ya da çalışan bütün Claude örnekleri.
    nonisolated static func applications(_ pid: pid_t?) -> [pid_t] {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).map(\.processIdentifier)
        guard let pid else { return running }
        return running.contains(pid) ? [pid] : []
    }

    /// Bir Claude örneğinin erişilebilirlik ağacını açar ya da kapatır; önceki değer döner (örnek yoksa ya da izin
    /// yoksa nil).
    @discardableResult
    public nonisolated static func setTreeEnabled(_ enabled: Bool, pid: pid_t) -> Bool? {
        guard AXIsProcessTrusted(), applications(pid) == [pid] else { return nil }
        let root = AXUIElementCreateApplication(pid)
        var previous: CFTypeRef?
        AXUIElementCopyAttributeValue(root, "AXManualAccessibility" as CFString, &previous)
        AXUIElementSetAttributeValue(root, "AXManualAccessibility" as CFString, enabled ? kCFBooleanTrue : kCFBooleanFalse)
        return (previous as? Bool) == true
    }

    /// Bulunamayınca tanı (yalnız debug derlemesi yazar): seçeneğin ya da sorunun metnini taşıyan öğelerin 4 üst
    /// grubunun yapısı (rol ve metinler, kısaltılmış). Sohbetin tamamını değil, kutunun çevresini gösterir.
    public nonisolated static func diagnosis(label: String, ask: String?, options: [String], pid: pid_t? = nil) -> String {
        let pids = applications(pid)
        guard AXIsProcessTrusted(), !pids.isEmpty else { return "izin yok ya da Claude kapalı" }
        let trees = pids.flatMap { pid -> [Node] in
            var windows: CFTypeRef?
            AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &windows)
            return ((windows as? [AXUIElement]) ?? []).map { snapshot($0) }
        }
        let keys = ([label] + options + [ask.map { String($0.prefix(30)) } ?? ""]).map(normalize).filter { !$0.isEmpty }
        var lines = ["örnekler \(pids) (istenen \(pid.map(String.init) ?? "hepsi")), pencere \(trees.count), aranan: \(keys)"]
        var shown = 0
        func outline(_ node: Node, depth: Int, limit: Int) {
            let texts = node.texts.map { "\"\($0.prefix(60))\"" }.joined(separator: " ")
            lines.append(String(repeating: "  ", count: depth) + node.role + (texts.isEmpty ? "" : " " + texts))
            guard depth < limit else { return }
            for child in node.children { outline(child, depth: depth + 1, limit: limit) }
        }
        func visit(_ node: Node, path: [Node]) {
            guard shown < 3 else { return }
            if node.texts.contains(where: { text in keys.contains { normalize(text).contains($0) } }) {
                shown += 1
                lines.append("--- eşleşen \(node.role), üst gruplar: \(path.prefix(4).map(\.role))")
                outline(path.prefix(4).last ?? node, depth: 0, limit: 7)
                return
            }
            for child in node.children { visit(child, path: [node] + path) }
        }
        for tree in trees { visit(tree, path: []) }
        if shown == 0 { lines.append("hiçbir öğede seçenek ya da soru metni yok") }
        return lines.joined(separator: "\n")
    }

    // MARK: - Ağaç ve eşleştirme (test edilebilir)

    /// AX ağacının anlık görüntüsü: rol, görünen metinler (başlık, açıklama, değer; boşlar yok), çocuklar.
    struct Node {
        var role: String
        var texts: [String]
        var children: [Node] = []
        var element: AnyObject?

        init(role: String, text: String, children: [Node] = [], element: AnyObject? = nil) {
            self.init(role: role, texts: text.isEmpty ? [] : [text], children: children, element: element)
        }

        init(role: String, texts: [String], children: [Node] = [], element: AnyObject? = nil) {
            self.role = role
            self.texts = texts
            self.children = children
            self.element = element
        }
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
        let texts = [string(kAXTitleAttribute), string(kAXDescriptionAttribute), string(kAXValueAttribute)].filter { !$0.isEmpty }
        var node = Node(role: role, texts: texts, element: element)
        guard depth < 80 else { return node }
        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        node.children = ((children as? [AXUIElement]) ?? []).map { snapshot($0, depth: depth + 1) }
        return node
    }

    /// Küçük harf, kısayol işaretleri ve Markdown imleri atılmış, boşluklar tek.
    nonisolated static func normalize(_ text: String) -> String {
        let dropped = text.lowercased().unicodeScalars.filter { !"⌘↩↵⏎⌥⇧⌃`*_".unicodeScalars.contains($0) }
        return String(String.UnicodeScalarView(dropped)).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Öğenin ve altının bütün metni (kutuda soruyu aramak için).
    nonisolated static func fullText(_ node: Node) -> String {
        (node.texts + node.children.map(fullText)).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Kısayol ipucu kelimeleri: düğmenin adının sonunda olabilir ("Evet ⌘ Enter").
    nonisolated static let shortcutWords: Set<String> = ["enter", "return", "cmd", "command", "ctrl", "control", "shift", "option", "alt", "+"]

    /// Düğmenin adlarından biri seçenekle aynı mı: başlık, açıklama ve değer tek tek, sonra içindeki metin; sondaki
    /// kısayol ipucu sayılmaz.
    nonisolated static func isNamed(_ node: Node, _ target: String) -> Bool {
        let names = node.texts + [node.children.map(fullText).filter { !$0.isEmpty }.joined(separator: " ")]
        return names.contains { name in
            let normalized = normalize(name)
            guard normalized.hasPrefix(target) else { return false }
            let rest = normalized.dropFirst(target.count).split(separator: " ").map(String.init)
            return rest.allSatisfy(shortcutWords.contains)
        }
    }

    nonisolated static func match(in trees: [Node], label: String, ask: String?, options: [String]) -> Match {
        let target = normalize(label)
        let others = options.map(normalize).filter { $0 != target && !$0.isEmpty }
        // Sorunun ilk 60 karakteri yeter; Markdown kod bölütleri metni parçalasa da tam metin birleştirilip aranır.
        let anchor = ask.map { String(normalize($0).prefix(60)) }.flatMap { $0.isEmpty ? nil : $0 }
        guard !target.isEmpty, anchor != nil || !others.isEmpty else { return .none }

        var found: [Node] = []
        func isButton(_ node: Node, named name: String) -> Bool {
            node.role == "AXButton" && isNamed(node, name)
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
