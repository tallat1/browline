import Foundation
import Observation

/// Hızlı not: tek metin, uygulama klasöründe düz dosya. Yazarken her tuşta değil, duraksayınca kaydedilir.
@MainActor
@Observable
public final class NotesStore {
    public var text: String {
        didSet { if text != oldValue { scheduleSave() } }
    }

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var isDirty = false

    public static let saveDelay: Duration = .milliseconds(600)

    public init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.talatozcoban.notchmvp")
        fileURL = base.appendingPathComponent("notes.txt")
        text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }

    /// Bekleyen kaydı hemen yazar (sekme kapanırken, uygulama çıkarken).
    public func flush() {
        saveTask?.cancel()
        saveTask = nil
        guard isDirty else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            isDirty = false
        } catch {
            Log.integrations.error("Not kaydedilemedi: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func scheduleSave() {
        isDirty = true
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }
}
