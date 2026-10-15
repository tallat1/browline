// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotchCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NotchShell", targets: ["NotchShell"]),
        .library(name: "ActivityEngine", targets: ["ActivityEngine"]),
        .library(name: "Integrations", targets: ["Integrations"]),
    ],
    targets: [
        // Pencere kabuğu: panel, geometri, şekil, hover. Uygulama içeriğinden habersiz.
        .target(name: "NotchShell"),
        // Hangi etkinliğin kompakt notch'ta görüneceğine karar veren öncelik motoru.
        .target(name: "ActivityEngine"),
        // Sistem entegrasyonları: Now Playing, pil, takvim, raf.
        .target(name: "Integrations"),
        .testTarget(
            name: "NotchCoreTests",
            dependencies: ["NotchShell", "ActivityEngine", "Integrations"]
        ),
    ]
)
