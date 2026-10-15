// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotchCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NotchShell", targets: ["NotchShell"]),
        .library(name: "ActivityEngine", targets: ["ActivityEngine"]),
        .library(name: "Integrations", targets: ["Integrations"]),
        .library(name: "ActivityAPI", targets: ["ActivityAPI"]),
        .library(name: "PrivateBridges", targets: ["PrivateBridges"]),
    ],
    targets: [
        // Pencere kabuğu: panel, geometri, şekil, hover. Uygulama içeriğinden habersiz.
        .target(name: "NotchShell"),
        // Hangi etkinliğin kompakt notch'ta görüneceğine karar veren öncelik motoru.
        .target(name: "ActivityEngine"),
        // Sistem entegrasyonları: Now Playing, pil, takvim, raf, gizlilik göstergesi, HUD.
        .target(name: "Integrations", dependencies: ["PrivateBridges"]),
        // Private API'nin tek yeri: semboller dlsym ile çözülür, yoksa özellik kapanır.
        .target(name: "PrivateBridges"),
        // Dış dünyaya açık etkinlik API'si: yerel soket protokolü, sunucu, istemci ve durum.
        .target(name: "ActivityAPI"),
        .testTarget(
            name: "NotchCoreTests",
            dependencies: ["NotchShell", "ActivityEngine", "Integrations", "ActivityAPI", "PrivateBridges"]
        ),
    ]
)
