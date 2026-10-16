import Integrations
import NotchShell
import SwiftUI

// MARK: - İzinler

struct PermissionsPage: View {
    let center: PermissionCenter

    var body: some View {
        let needed = PermissionKind.allCases.filter(center.isNeeded)
        let unused = PermissionKind.allCases.filter { !center.isNeeded($0) }
        SettingsForm(page: .permissions) {
            Section {
                if needed.isEmpty {
                    SettingsNote("Açık özelliklerin hiçbiri izin istemiyor.")
                } else {
                    ForEach(needed) { PermissionRow(kind: $0, center: center, showsIcon: true) }
                }
            } header: {
                Text("Açık özellikler için")
            } footer: {
                SettingsNote("İzin her özelliğin kendi sayfasında da görünür. Sistem Ayarları'ndan dönünce durum kendiliğinden yenilenir.")
            }
            if !unused.isEmpty {
                Section("Kullanılmayan") {
                    ForEach(unused) { kind in
                        HStack(spacing: 10) {
                            SettingsIcon(symbol: kind.symbol, tint: .gray, size: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: kind.systemName)
                                Text(verbatim: kind.purpose).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("Özellik kapalı").font(.caption).foregroundStyle(.secondary)
                        }
                        .settingsAnchor("permission.\(kind.rawValue)")
                    }
                }
            }
        }
        .onAppear { center.refresh() }
    }
}
