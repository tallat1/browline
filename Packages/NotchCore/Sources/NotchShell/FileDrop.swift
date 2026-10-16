import AppKit
import UniformTypeIdentifiers

/// Notch'a bırakılan dosyalar. Üç biçim gelir:
/// - Dosya adresi (Finder).
/// - Dosya sözü (`NSFilePromiseProvider`): ekran görüntüsü/kaydının sağ alttaki küçük resmi, Fotoğraflar,
///   Mail eki. Dosya ancak bırakılınca yazılır; adres olmadığı için eskiden algılanmıyordu (kullanıcı
///   2026-10-16: "ekran görüntüsünü rafa koyamıyorum").
/// - Yalnız görsel verisi (tarayıcıdan görsel): PNG olarak yazılır.
public enum FileDrop {
    static let promiseTypes: [NSPasteboard.PasteboardType] =
        NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
    static let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff]

    /// Bırakma katmanının kayıtlı olduğu türler.
    public static let acceptedTypes: [NSPasteboard.PasteboardType] = [.fileURL] + promiseTypes + imageTypes

    /// Sürüklenen şey dosya, dosya sözü ya da yalnız görsel mi (metin sürüklemesi notch'u açmasın).
    public static func carriesFiles(_ pasteboard: NSPasteboard) -> Bool {
        if pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) { return true }
        let types = Set(pasteboard.types ?? [])
        if !types.isDisjoint(with: promiseTypes) { return true }
        return !types.isDisjoint(with: imageTypes) && !types.contains(.string)
    }

    /// Bırakılanları dosyaya çevirir; `handler` her hazır parti için ana iş parçacığında çağrılır (söz
    /// birden çok dosya getirebilir). Geçici klasördeki adresler (başka uygulamanın geçici öğesi, sonra
    /// silinir) hedefe kopyalanır.
    /// ⛔ `performDragOperation` içinden EŞZAMANLI çağrılmalı: `receivePromisedFiles` başka anda
    /// NSInternalInconsistencyException fırlatır (2026-10-16 denemesi); araya async girmesin.
    @MainActor
    public static func receive(from pasteboard: NSPasteboard, destination: URL,
                               handler: @escaping @MainActor ([URL]) -> Void) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !urls.isEmpty {
            handler(urls.map { isTemporary($0) ? (copy($0, to: destination) ?? $0) : $0 })
            return
        }
        let receivers = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver] ?? []
        if !receivers.isEmpty {
            try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            for receiver in receivers {
                receiver.receivePromisedFiles(atDestination: destination, options: [:], operationQueue: promiseQueue) { url, error in
                    if let error {
                        Log.shell.error("dosya sözü alınamadı: \(error.localizedDescription, privacy: .public)")
                        return
                    }
                    DispatchQueue.main.async { MainActor.assumeIsolated { handler([url]) } }
                }
            }
            return
        }
        if let url = writeImage(from: pasteboard, to: destination) { handler([url]) }
    }

    private static let promiseQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        return queue
    }()

    /// /var/folders altındaki geçici öğeler (ör. `TemporaryItems/NSIRD_screencaptureui_…`).
    static func isTemporary(_ url: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().path
        return path.hasPrefix("/private/var/folders/") || path.hasPrefix("/var/folders/")
    }

    static func copy(_ url: URL, to directory: URL) -> URL? {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = unique(directory.appendingPathComponent(url.lastPathComponent))
        do {
            try FileManager.default.copyItem(at: url, to: target)
            return target
        } catch {
            return nil
        }
    }

    static func writeImage(from pasteboard: NSPasteboard, to directory: URL, now: Date = .now) -> URL? {
        guard let image = NSImage(pasteboard: pasteboard), let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = unique(directory.appendingPathComponent(String(localized: "Görsel \(formatter.string(from: now)).png")))
        do {
            try png.write(to: target)
            return target
        } catch {
            return nil
        }
    }

    static func unique(_ base: URL) -> URL {
        var candidate = base
        var counter = 2
        let stem = base.deletingPathExtension().lastPathComponent
        let ext = base.pathExtension
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = base.deletingLastPathComponent()
                .appendingPathComponent(ext.isEmpty ? "\(stem) \(counter)" : "\(stem) \(counter).\(ext)")
            counter += 1
        }
        return candidate
    }
}

/// Panelin en üstünde, yalnız dosya sürüklenirken isabet alan bırakma katmanı: tıklamalar ve imleç
/// her zaman alttaki içeriğe gider. Kendi raf öğemizi sürüklerken (kaynak bu uygulama, genel izleyici
/// görmez) devreye girmez; öğe rafa ikinci kez eklenmez.
final class FileDropView: NSView {
    weak var model: NotchSurfaceModel?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes(FileDrop.acceptedTypes)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) kullanılmıyor") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        model?.isFileDragActive == true ? super.hitTest(point) : nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        model?.isDropTargeted = false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        model?.isDropTargeted = false
        guard let model, model.isOpen, let onFileDrop = model.onFileDrop else { return false }
        return onFileDrop(sender.draggingPasteboard)
    }

    private func update(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let model, model.isOpen, model.onFileDrop != nil,
              FileDrop.carriesFiles(sender.draggingPasteboard) else { return [] }
        model.isDropTargeted = true
        return .copy
    }
}
