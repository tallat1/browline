import Foundation
import UniformTypeIdentifiers

/// Raftaki dosyayı dönüştürür; sonuç kaynağın yanına (yazılamıyorsa İndirilenler'e) yeni dosya olarak
/// yazılır, özgün dosyaya dokunulmaz. Yalnız macOS'un kendi araçları: görsel `sips`, video ve ses
/// `avconvert` (ffmpeg gerekmez, izin istemez).
public enum ShelfConversion: Hashable, Sendable {
    public enum ImageFormat: String, CaseIterable, Sendable {
        case jpeg, png, heic

        var fileExtension: String { self == .jpeg ? "jpg" : rawValue }
        var type: UTType { self == .jpeg ? .jpeg : (self == .png ? .png : .heic) }
    }

    public enum VideoPreset: String, CaseIterable, Sendable {
        case p1080, p720

        var avconvertPreset: String { self == .p1080 ? "Preset1920x1080" : "Preset1280x720" }
        var suffix: String { self == .p1080 ? "1080p" : "720p" }
    }

    /// Görsel biçimi değişir.
    case image(ImageFormat)
    /// En uzun kenar en çok bu kadar piksel; biçim aynı kalır.
    case resize(maxPixels: Int)
    /// MP4 (H.264).
    case video(VideoPreset)
    /// Videonun sesi M4A olarak.
    case audio

    public static let resizeOptions = [2048, 1280]

    /// Dosyaya uygulanabilen dönüşümler (aynı biçime dönüşüm yok).
    public static func options(for url: URL) -> [ShelfConversion] {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return [] }
        if type.conforms(to: .image), type != .gif, type != .svg {
            let formats = ImageFormat.allCases.filter { !type.conforms(to: $0.type) }.map(ShelfConversion.image)
            return formats + resizeOptions.map { .resize(maxPixels: $0) }
        }
        if type.conforms(to: .movie) || type.conforms(to: .video) {
            return VideoPreset.allCases.map(ShelfConversion.video) + [.audio]
        }
        return []
    }

    public var title: String {
        switch self {
        case let .image(format):
            String(localized: "\(format.rawValue.uppercased()) olarak kaydet")
        case let .resize(maxPixels):
            String(localized: "Küçült (en çok \(maxPixels) px)")
        case let .video(preset):
            String(localized: "MP4 olarak kaydet (\(preset.suffix))")
        case .audio:
            String(localized: "Sesi ayıkla (M4A)")
        }
    }

    /// Sonuç dosyasının adı: biçim değişince yalnız uzantı, küçültmede ve videoda ek.
    func outputName(for source: URL) -> String {
        let stem = source.deletingPathExtension().lastPathComponent
        switch self {
        case let .image(format): return "\(stem).\(format.fileExtension)"
        case let .resize(maxPixels): return "\(stem) \(maxPixels)px.\(source.pathExtension)"
        case let .video(preset): return "\(stem) \(preset.suffix).mp4"
        case .audio: return "\(stem).m4a"
        }
    }
}

public enum ShelfConverter {
    /// Arka planda çalışır; sonuç ana iş parçacığında (başarısızsa nil).
    public static func convert(_ source: URL, _ conversion: ShelfConversion,
                               downloads: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0],
                               completion: @escaping @MainActor (URL?) -> Void) {
        let destination = ShelfStore.unique(ShelfStore.outputDirectory(for: source, downloads: downloads)
            .appendingPathComponent(conversion.outputName(for: source)))
        Task.detached(priority: .userInitiated) {
            let result = run(conversion, source: source, destination: destination)
            await MainActor.run { completion(result) }
        }
    }

    nonisolated static func run(_ conversion: ShelfConversion, source: URL, destination: URL) -> URL? {
        let status: Int32
        switch conversion {
        case let .image(format):
            var arguments = ["-s", "format", format.rawValue]
            if format == .jpeg || format == .heic { arguments += ["-s", "formatOptions", "85"] }
            status = ShelfStore.run("/usr/bin/sips", arguments + [source.path, "--out", destination.path])
        case let .resize(maxPixels):
            status = ShelfStore.run("/usr/bin/sips", ["-Z", String(maxPixels), source.path, "--out", destination.path])
        case let .video(preset):
            status = ShelfStore.run("/usr/bin/avconvert", ["--preset", preset.avconvertPreset, "--source", source.path,
                                                          "--output", destination.path])
        case .audio:
            status = ShelfStore.run("/usr/bin/avconvert", ["--preset", "PresetAppleM4A", "--source", source.path,
                                                          "--output", destination.path])
        }
        guard status == 0, FileManager.default.fileExists(atPath: destination.path) else {
            Log.integrations.error("Raf dönüşümü başarısız: çıkış \(status)")
            try? FileManager.default.removeItem(at: destination)
            return nil
        }
        Log.integrations.notice("Raf: dosya dönüştürüldü")
        return destination
    }
}
