import Foundation

/// İndirilen (notarize edilmemiş) DMG'den kopyalanan paketin her dosyası `com.apple.quarantine` taşır.
/// Kullanıcı uygulamayı Gizlilik ve Güvenlik'ten açtığında onay ana uygulamayı kapsar; `/usr/bin/perl`'ün
/// yüklediği gömülü çerçeve ve yardımcılar ayrıca denetlenip engellenebilir (Now Playing sessizce Music/Spotify
/// yedeğine düşer). Uygulama çalıştığına göre kullanıcı onaylamıştır: kendi paketindeki yardımcıların işareti
/// kaldırılır. Öznitelik imzanın parçası değil; imza bozulmaz. Yazılamayan konumda (salt okunur DMG) sessizce geçer.
enum HelperQuarantine {
    static let attribute = "com.apple.quarantine"

    static func clear(in bundle: Bundle = .main) {
        let contents = bundle.bundleURL.appendingPathComponent("Contents", isDirectory: true)
        let roots = ["Frameworks", "Helpers", "Resources"].map { contents.appendingPathComponent($0, isDirectory: true) }
        var cleared = 0
        for root in roots {
            guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { continue }
            let urls = [root] + walker.compactMap { $0 as? URL }
            for url in urls where getxattr(url.path, attribute, nil, 0, 0, XATTR_NOFOLLOW) >= 0 {
                if removexattr(url.path, attribute, XATTR_NOFOLLOW) == 0 { cleared += 1 }
            }
        }
        if cleared > 0 { AppLog.coordinator.notice("karantina işareti kaldırıldı: \(cleared) yardımcı dosya") }
    }
}
