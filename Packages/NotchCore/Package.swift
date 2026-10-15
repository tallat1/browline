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
    ],
    targets: [
        // Pencere kabuğu: panel, geometri, şekil, hover. Uygulama içeriğinden habersiz.
        .target(name: "NotchShell"),
        // Hangi etkinliğin kompakt notch'ta görüneceğine karar veren öncelik motoru.
        .target(name: "ActivityEngine"),
        // Sistem entegrasyonları: Now Playing, pil, takvim, raf.
        .target(name: "Integrations"),
        // Dış dünyaya açık etkinlik API'si: yerel soket protokolü, sunucu, istemci ve durum.
        .target(name: "ActivityAPI"),
        .testTarget(
            name: "NotchCoreTests",
            dependencies: ["NotchShell", "ActivityEngine", "Integrations", "ActivityAPI"]
        ),
    ]
)
