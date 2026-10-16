import Integrations
import NotchShell
import SwiftUI

/// Claude plan limitleri: 5 saatlik oturum ve haftalık pencere. Veri Claude Code durum satırından
/// gelir; yalnız bir oturum çalışırken tazelendiği için son güncelleme zamanı da gösterilir.
struct ClaudeTab: View {
    let usage: ClaudeUsageMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let account = usage.account {
                AccountRow(account: account).notchTransition(.fade)
            }
            // Veri gelince boş durumdan kartlara çapraz geçiş; yüzdeler akarak değişir.
            ZStack {
                stateContent
                    .id(stateKey)
                    .notchTransition(.swap)
            }
            .notchAnimation(value: stateKey)
        }
        .notchAnimation(value: usage.account)
        // Hesap ve durum satırı izi sekme her açıldığında yeniden okunur (hesap değişmiş olabilir).
        .onAppear { usage.refreshSeen() }
    }

    @ViewBuilder
    private var stateContent: some View {
        if let current = usage.usage {
            TimelineView(.everyMinute) { timeline in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        WindowCard(title: "Oturum · 5 saat", window: current.fiveHour, now: timeline.currentDate, relative: true)
                        WindowCard(title: "Haftalık", window: current.sevenDay, now: timeline.currentDate, relative: false)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Label(updatedText(current.capturedAt, now: timeline.currentDate), systemImage: "clock")
                        .font(NotchDesign.caption)
                        .foregroundStyle(NotchDesign.metadata)
                        .labelStyle(MetadataLabelStyle())
                }
            }
        } else if let problem = apiProblem, usage.activeLimits.isEmpty {
            EmptyStateView(symbol: problem.symbol, title: problem.title, message: problem.message)
        } else if !usage.activeLimits.isEmpty {
            // Oturum kayıtlarından: limit doldu, ne zaman sıfırlanacak (yüzde yok).
            TimelineView(.everyMinute) { timeline in
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(usage.activeLimits.filter { $0.resetsAt > timeline.currentDate }.prefix(2), id: \.type) { hit in
                        LimitHitCard(hit: hit, now: timeline.currentDate).notchTransition(.listItem)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else if usage.statuslineSeenAt != nil {
            // Betik çalışıyor ama limit gelmiyor: hesap Pro/Max değil ya da oturumda henüz yanıt yok.
            EmptyStateView(symbol: "sparkles", title: "Durum satırı çalışıyor, limit gelmedi",
                           message: "Claude yalnız Pro ve Max aboneliklerinde, oturumdaki ilk yanıttan sonra limit bildirir.")
        } else {
            // 2026-10-16: masaüstü uygulaması durum satırını çalıştırmıyor; yüzdeleri yalnız terminaldeki
            // Claude Code bildiriyor.
            EmptyStateView(symbol: "checkmark.circle", title: "Dolmuş bir limit yok",
                           message: "Bir limit dolarsa ne zaman sıfırlanacağı burada görünür. Kullanım yüzdelerini yalnız terminaldeki Claude Code bildiriyor.")
        }
    }

    private var stateKey: Int {
        if usage.usage != nil { return 2 }
        if !usage.activeLimits.isEmpty { return 3 }
        if apiProblem != nil { return 4 }
        return usage.statuslineSeenAt != nil ? 1 : 0
    }

    /// Uç nokta açık ama veri yoksa kullanıcıya ne yapacağı söylenir.
    private var apiProblem: (symbol: String, title: LocalizedStringKey, message: LocalizedStringKey)? {
        switch usage.apiStatus {
        case .off, .ok: nil
        case .waiting:
            ("hourglass", "Limitler alınıyor…", "Anahtar Zinciri izni istenirse \"Her zaman izin ver\" seçin.")
        case .noCredentials:
            ("key", "Claude Code oturumu bulunamadı",
             "Terminalde claude auth login ile oturum açın; Anahtar Zinciri izni istenirse \"Her zaman izin ver\" seçin.")
        case .expired:
            ("clock.badge.exclamationmark", "Oturum anahtarının süresi dolmuş",
             "Terminalde claude komutunu bir kez çalıştırın; Claude Code anahtarı yeniler.")
        case .unauthorized:
            ("lock", "Anahtar reddedildi", "Terminalde claude auth login ile yeniden oturum açın.")
        case .rateLimited:
            ("tortoise", "Claude çok fazla istek dedi", "Biraz sonra kendiliğinden yeniden denenecek.")
        case .failed:
            ("exclamationmark.triangle", "Limitler alınamadı", "Bağlantı ya da uç nokta sorunu; birazdan yeniden denenecek.")
        }
    }

    private func updatedText(_ captured: Date, now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(captured) / 60)
        if usage.usageSource == .api {
            // Uç noktadan: 5 dk'da bir tazelenir, oturum açık olması gerekmez.
            if minutes < 1 { return String(localized: "Az önce güncellendi · 5 dakikada bir tazelenir") }
            return String(localized: "\(minutes) dk önce güncellendi · 5 dakikada bir tazelenir")
        }
        if minutes < 1 { return String(localized: "Az önce güncellendi") }
        if minutes < 60 { return String(localized: "\(minutes) dk önce güncellendi · Claude Code oturumu açıkken tazelenir") }
        return String(localized: "\(minutes / 60) sa önce güncellendi · Claude Code oturumu açıkken tazelenir")
    }
}

private struct WindowCard: View {
    let title: LocalizedStringKey
    let window: ClaudeUsageMonitor.Window?
    let now: Date
    let relative: Bool

    var body: some View {
        if let window {
            MetricCard(title: title, value: NowFormat.percent(window.usedPercentage.rounded()),
                       unit: String(localized: "kullanıldı"), level: window.usedPercentage / 100,
                       tint: tint(for: window.usedPercentage),
                       context: window.resetsAt.flatMap { $0 > now ? shortReset($0) : nil },
                       contextSymbol: "arrow.counterclockwise",
                       contextHelp: window.resetsAt.flatMap { $0 > now ? resetText($0) : nil })
        } else {
            MetricCard(title: title, value: "–", unit: String(localized: "veri yok"))
        }
    }

    private func tint(for percent: Double) -> Color {
        percent >= 90 ? .red : (percent >= 75 ? .orange : Color(red: 0.85, green: 0.47, blue: 0.34))
    }

    /// Kartın sağ üstü için kısa biçim: "3 sa 9 dk", "42 dk", "Salı 12:00".
    private func shortReset(_ reset: Date) -> String {
        guard relative else { return reset.formatted(.dateTime.weekday(.wide).hour().minute()) }
        let minutes = Int((reset.timeIntervalSince(now) / 60).rounded(.up))
        return minutes < 60 ? String(localized: "\(minutes) dk") : String(localized: "\(minutes / 60) sa \(minutes % 60) dk")
    }

    private func resetText(_ reset: Date) -> String {
        if relative {
            let minutes = Int((reset.timeIntervalSince(now) / 60).rounded(.up))
            return minutes < 60
                ? String(localized: "\(minutes) dk sonra sıfırlanır")
                : String(localized: "\(minutes / 60) sa \(minutes % 60) dk sonra sıfırlanır")
        }
        return String(localized: "\(reset.formatted(.dateTime.weekday(.wide).hour().minute())) sıfırlanır")
    }
}

/// Etkin Claude hesabı: ad/e-posta, kuruluş ve plan rozeti. Uzun e-posta üzerine gelince kayar.
private struct AccountRow: View {
    let account: ClaudeAccount

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                MarqueeText(text: account.email ?? account.displayName ?? "", size: 12, weight: .semibold, trigger: .hover)
                if let organization = account.organizationName {
                    Text(verbatim: organization).font(NotchDesign.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let plan = account.plan {
                Text(verbatim: plan)
                    .font(NotchDesign.captionEmphasized)
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .background(Capsule().fill(Color(red: 0.85, green: 0.47, blue: 0.34).opacity(0.25)))
                    .foregroundStyle(Color(red: 0.95, green: 0.62, blue: 0.5))
            }
        }
        .help(account.fetchedAt.map {
            String(localized: "Claude Code'un etkin hesabı · profil \($0.formatted(date: .abbreviated, time: .shortened))")
        } ?? String(localized: "Claude Code'un etkin hesabı"))
    }
}

/// Dolmuş limit: hangi pencere, ne zaman ve ne kadar sonra sıfırlanacak.
private struct LimitHitCard: View {
    let hit: ClaudeLimitHit
    let now: Date

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.system(size: 18))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(NotchDesign.bodyEmphasized)
                Text(detail).font(NotchDesign.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .notchCard()
    }

    private var title: String {
        if hit.isWeekly {
            return hit.modelSuffix.map { String(localized: "Haftalık limit doldu (\($0))") }
                ?? String(localized: "Haftalık limit doldu")
        }
        return String(localized: "5 saatlik oturum limiti doldu")
    }

    private var detail: String {
        let minutes = max(1, Int((hit.resetsAt.timeIntervalSince(now) / 60).rounded(.up)))
        let relative = minutes < 60 ? String(localized: "\(minutes) dk sonra")
                                    : String(localized: "\(minutes / 60) sa \(minutes % 60) dk sonra")
        let clock = hit.resetsAt.formatted(Calendar.current.isDateInToday(hit.resetsAt)
                                           ? .dateTime.hour().minute()
                                           : .dateTime.weekday(.wide).hour().minute())
        return String(localized: "\(clock) sıfırlanır · \(relative)")
    }
}
