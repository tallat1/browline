import Foundation

/// Borudan satır satır okur (olay tabanlı, `readabilityHandler`). `FileHandle.bytes` kullanılmaz:
/// okumaları ortak bir yürütücüde sıraya giriyor ve veri beklemeyen bir akış diğerini tamamen
/// durduruyor (2026-10-16: uyarlayıcı sessizken oturum yardımcısı hiç okunmadı, boru dolunca
/// yardımcı `write`'ta kaldı).
final class PipeLineReader: @unchecked Sendable {
    private let handle: FileHandle
    /// Yalnız okuyucunun seri kuyruğundan çağrılır; çözücü durumu burada tutulabilir.
    private let onLine: (String) -> Void
    private var buffer = Data()

    init(handle: FileHandle, onLine: @escaping (String) -> Void) {
        self.handle = handle
        self.onLine = onLine
    }

    func start() {
        handle.readabilityHandler = { [self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                // Dosya sonu: süreç çıktı; çıkış terminationHandler'dan raporlanır.
                handle.readabilityHandler = nil
                return
            }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
                buffer.removeSubrange(buffer.startIndex...newline)
                onLine(line)
            }
        }
    }
}
