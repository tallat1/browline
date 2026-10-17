import ActivityAPI
import ActivityEngine
import AppKit
import Integrations
import NotchShell
import Observation
import SwiftUI

/// Dış dünyanın notch'a ulaştığı kapılar: soket sunucusu, URL şeması, Kestirmeler ve onay soruları.
extension AppCoordinator {
    /// URL şeması ve Kestirmeler soketi dolaşmadan buradan girer: aynı doğrulama, aynı ayar.
    func handleExternal(_ request: ActivityRequest, source: String) -> ActivityResponse {
        guard settings.activityAPIEnabled else {
            AppLog.coordinator.notice("\(source, privacy: .public) \(request.op.rawValue, privacy: .public): API kapalı")
            return .failure(String(localized: "Etkinlik API'si kapalı; Ayarlar › Şimdi › Dış etkinlikler'den açın."))
        }
        let response = externalActivities.handle(request)
        // Başlık kişisel olabilir; günlüğe yalnız işlem ve sonuç.
        AppLog.coordinator.notice("\(source, privacy: .public) \(request.op.rawValue, privacy: .public): \(response.ok ? "tamam" : response.error ?? "hata", privacy: .public)")
        return response
    }

    func handleURL(_ url: URL) {
        // Web sayfaları da bu bağlantıyı açabilir: ayrı anahtar, varsayılan kapalı; ayrıştırmadan önce denetlenir.
        guard settings.activityAPIEnabled, settings.urlSchemeEnabled else {
            AppLog.coordinator.notice("URL yok sayıldı: URL şeması kapalı")
            return
        }
        do throws(ActivityURL.ParseError) {
            _ = handleExternal(try ActivityURL.request(from: url), source: "URL")
        } catch {
            AppLog.coordinator.error("URL reddedildi: \(error.description, privacy: .public)")
        }
    }

    /// Kompakt görünüm için: öne çıkan kimliğe karşılık gelen dış etkinlik ya da kısa bildirim.
    func externalActivity(for id: ActivityID?) -> ExternalActivity? {
        guard let id else { return nil }
        if id == ActivityKind.externalFlash { return externalActivities.flash }
        return externalActivities.activities.first { ActivityKind.externalPrefix + $0.id == id.rawValue }
    }

    var cliPath: String {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/notch").path
    }

    func setActivityAPI(enabled: Bool) {
        if enabled, activityServer == nil {
            let store = externalActivities
            let questions = questions
            let server = ActivitySocketServer { request in
                switch request.op {
                case .ask: await questions.ask(request)
                case .dismiss: await questions.dismiss(request)
                default: await store.handle(request)
                }
            }
            do {
                try server.start()
                activityServer = server
                ui.activityAPIStatus = String(localized: "Dinliyor: \(server.socketURL.path)")
            } catch {
                ui.activityAPIStatus = String(localized: "Başlatılamadı: \(String(describing: error))")
            }
        } else if !enabled, let server = activityServer {
            server.stop()
            activityServer = nil
            ui.activityAPIStatus = String(localized: "Kapalı")
            syncExternal([])
            activities.cancelFlash(ActivityKind.externalFlash)
        }
    }

    /// Yeni soru gelince notch açılır ve sabitlenir (pencere etkinleşmez, yazı yazılan uygulama bölünmez);
    /// kapalı notch'ta "izin istiyor" canlı etkinliği görünür. Son soru yanıtlanınca yalnız soru yüzünden
    /// açılan notch'lar kapanır.
    func questionsChanged(_ list: [ExternalQuestion]) {
        let ids = Set(list.map(\.id))
        let arrived = !ids.subtracting(shownQuestionIDs).isEmpty
        shownQuestionIDs = ids
        if let first = list.first {
            _ = externalActivities.handle(ActivityRequest(
                op: .push, id: Self.questionActivityID, title: first.title, subtitle: first.subtitle,
                symbol: first.symbol ?? "hand.raised.fill", tint: first.tint ?? "#FF9F0A",
                priority: ActivityKind.questionPriority, ttl: max(1, first.expiresAt.timeIntervalSinceNow)),
                isInternal: true)
            if arrived {
                AppLog.coordinator.notice("onay sorusu geldi (\(list.count) bekliyor): \(first.subtitle ?? first.title, privacy: .private)")
                for model in panels.models where !model.isOpen {
                    model.tapped()
                    questionOpenedModels.append(ObjectIdentifier(model))
                }
            }
        } else {
            _ = externalActivities.handle(ActivityRequest(op: .end, id: Self.questionActivityID), isInternal: true)
            let opened = Set(questionOpenedModels)
            for model in panels.models where opened.contains(ObjectIdentifier(model)) { model.dismiss() }
            questionOpenedModels.removeAll()
        }
    }

    static let questionActivityID = "notch.question"

    func syncExternal(_ list: [ExternalActivity]) {
        let wanted = Set(list.map { ActivityID(ActivityKind.externalPrefix + $0.id) })
        for id in liveExternalIDs where !wanted.contains(id) { activities.removeLive(id) }
        for activity in list {
            activities.setLive(ActivityID(ActivityKind.externalPrefix + activity.id), priority: activity.priority)
        }
        liveExternalIDs = wanted
    }
}
