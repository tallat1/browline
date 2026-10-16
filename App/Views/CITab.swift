import Integrations
import NotchShell
import SwiftUI

/// Durum › CI: izlenen depolardaki son GitHub Actions çalışmaları. Satıra basınca tarayıcıda açılır.
struct CITab: View {
    let ci: CIMonitor
    let hasRepositories: Bool
    /// Ayarlar › Durum › CI'ı açar ve satırı vurgular.
    let openSettings: () -> Void

    var body: some View {
        ZStack {
            content
                .id(ci.runs.isEmpty)
                .notchTransition(.swap)
        }
        .notchAnimation(value: ci.runs.isEmpty)
    }

    @ViewBuilder
    private var content: some View {
        if case .missingTool = ci.status {
            EmptyStateView(symbol: "hammer", title: "gh bulunamadı",
                           message: "GitHub Actions durumu kendi gh oturumunuzla okunur: Terminal'de brew install gh, sonra gh auth login.")
        } else if !hasRepositories {
            EmptyStateView(symbol: "hammer", title: "İzlenen depo yok",
                           message: "İzlenecek GitHub depolarını ayarlardan ekleyin.") {
                Button("Depo ekle…", action: openSettings)
                    .buttonStyle(QuietButtonStyle())
            }
        } else if ci.runs.isEmpty {
            if case let .failed(repository) = ci.status {
                EmptyStateView(symbol: "exclamationmark.triangle", title: "Çalışmalar okunamadı",
                               message: "\(repository) — gh auth status ile oturumu ve depo erişimini kontrol edin.")
            } else {
                EmptyStateView(symbol: "checkmark.seal", title: "Son çalışma yok")
            }
        } else {
            ScrollView {
                LazyVStack(spacing: NotchDesign.Space.xxs) {
                    ForEach(ci.runs) { run in
                        CIRunRow(run: run).notchTransition(.listItem)
                    }
                }
                .notchAnimation(value: ci.runs.map(\.id))
            }
            .scrollIndicators(.never)
        }
    }
}

private struct CIRunRow: View {
    let run: CIMonitor.Run
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: NotchDesign.Space.m + 2) {
            CIStateIcon(state: run.state)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: run.workflow.isEmpty ? run.title : "\(run.workflow) · \(run.title)")
                    .font(NotchDesign.body)
                    .lineLimit(1)
                    .truncationMode(.tail)
                TimelineView(.everyMinute) { timeline in
                    Text(verbatim: meta(now: timeline.currentDate))
                        .font(NotchDesign.caption)
                        .foregroundStyle(NotchDesign.metadata)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: NotchDesign.Space.s)
        }
        .padding(.horizontal, NotchDesign.Space.m)
        .frame(height: 38)
        .background(RoundedRectangle(cornerRadius: NotchDesign.Radius.small, style: .continuous)
            .fill(isHovering ? NotchDesign.cardHoverFill : .clear))
        .contentShape(Rectangle())
        .onTapGesture { if let url = run.url { NSWorkspace.shared.open(url) } }
        .onHover { isHovering = $0 }
        .notchAnimation(NotchMotion.hover, value: isHovering)
        .help(run.url == nil ? run.repository : String(localized: "Tarayıcıda aç"))
    }

    private func meta(now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(run.createdAt) / 60)
        let when = minutes < 1 ? String(localized: "az önce")
            : (minutes < 60 ? String(localized: "\(minutes) dk önce")
               : run.createdAt.formatted(date: .abbreviated, time: .shortened))
        return [run.repositoryName, run.branch, when].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// Çalışma durumu simgesi: süren turuncu, başarılı yeşil, başarısız kırmızı, diğer gri.
struct CIStateIcon: View {
    let state: CIMonitor.Run.State

    var body: some View {
        Image(systemName: Self.symbol(for: state))
            .font(.system(size: NotchDesign.Icon.regular, weight: .semibold))
            .foregroundStyle(Self.tint(for: state))
    }

    static func symbol(for state: CIMonitor.Run.State) -> String {
        switch state {
        case .active: "circle.dotted.circle"
        case .success: "checkmark.circle.fill"
        case .failure: "xmark.octagon.fill"
        case .other: "minus.circle.fill"
        }
    }

    static func tint(for state: CIMonitor.Run.State) -> Color {
        switch state {
        case .active: .orange
        case .success: .green
        case .failure: .red
        case .other: .secondary
        }
    }
}
