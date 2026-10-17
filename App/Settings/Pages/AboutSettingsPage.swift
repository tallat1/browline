import Integrations
import NotchShell
import SwiftUI

// MARK: - Hakkında

struct AboutSettingsPage: View {
    let coordinator: AppCoordinator

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    private static func license(_ name: String) -> String {
        Bundle.main.url(forResource: name, withExtension: "txt")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? String(localized: "Lisans metni bulunamadı.")
    }

    var body: some View {
        SettingsForm(page: .about) {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "Browline").font(.title2.weight(.semibold))
                        Text("Sürüm \(version)").foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                .settingsAnchor("about")
            }
            Section("Üçüncü taraf yazılım") {
                DisclosureGroup("mediaremote-adapter (ungive), BSD-3-Clause") {
                    licenseText(Self.license("mediaremote-adapter-LICENSE"))
                }
                DisclosureGroup("SwiftTerm (Miguel de Icaza), MIT") {
                    licenseText(Self.license("SwiftTerm-LICENSE"))
                }
                DisclosureGroup("Sparkle (Sparkle Project), MIT") {
                    licenseText(Self.license("Sparkle-LICENSE"))
                }
            }
        }
    }

    private func licenseText(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
