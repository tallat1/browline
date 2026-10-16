import AppKit
import CoreAudio
import Foundation
import Testing
@testable import Integrations

@MainActor
struct CIMonitorTests {
    // gh run list --json çıktısının biçimi (örnek değerler).
    static let sample = #"[{"conclusion":"","createdAt":"2026-10-16T09:58:01Z","databaseId":101,"displayTitle":"Örnek değişiklik","headBranch":"main","status":"in_progress","url":"https://github.com/ornek/depo/actions/runs/101","workflowName":"CI"},{"conclusion":"failure","createdAt":"2026-10-16T09:00:00Z","databaseId":100,"displayTitle":"Önceki","headBranch":"main","status":"completed","url":"https://github.com/ornek/depo/actions/runs/100","workflowName":"CI"}]"#

    @Test func parsesRuns() {
        let runs = CIMonitor.parse(Data(Self.sample.utf8), repository: "ornek/depo")
        #expect(runs.map(\.id) == [101, 100])
        #expect(runs[0].state == .active)
        #expect(runs[1].state == .failure)
        #expect(runs[0].repositoryName == "depo")
        #expect(runs[0].url?.absoluteString.hasSuffix("/101") == true)
    }

    @Test func normalizesRepositoryNames() {
        #expect(CIMonitor.normalize("https://github.com/ornek/depo.git") == "ornek/depo")
        #expect(CIMonitor.normalize("git@github.com:tallat1/notch.git") == "tallat1/notch")
        #expect(CIMonitor.normalize(" ornek/depo ") == "ornek/depo")
        #expect(CIMonitor.normalize("tek-parca") == nil)
        let config = "[core]\n\tbare = false\n[remote \"origin\"]\n\turl = git@github.com:ornek/depo.git\n"
        #expect(CIMonitor.originURL(in: config) == "git@github.com:ornek/depo.git")
    }

    @Test func reportsFinishedRunOnce() {
        let monitor = CIMonitor()
        var finished: [Int] = []
        monitor.onRunFinished = { finished.append($0.id) }
        let active = CIMonitor.parse(Data(Self.sample.utf8), repository: "ornek/depo")
        monitor.apply(active)  // ilk okuma: bitmiş 100 bildirilmez
        #expect(finished.isEmpty)
        #expect(monitor.activeRuns.map(\.id) == [101])
        let done = CIMonitor.Run(id: 101, repository: "ornek/depo", workflow: "CI", title: "Örnek değişiklik",
                                 branch: "main", state: .success, createdAt: active[0].createdAt, url: nil)
        monitor.apply([done, active[1]])
        monitor.apply([done, active[1]])
        #expect(finished == [101])
        #expect(monitor.activeRuns.isEmpty)
    }
}
