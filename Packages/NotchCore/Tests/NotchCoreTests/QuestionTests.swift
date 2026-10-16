import Foundation
import Testing
@testable import ActivityAPI

@MainActor
struct QuestionStoreTests {
    private func waitForQuestion(_ store: QuestionStore) async {
        while store.questions.isEmpty { await Task.yield() }
    }

    @Test func answerResolvesWaitingAsk() async {
        let store = QuestionStore()
        let task = Task { await store.ask(ActivityRequest(op: .ask, id: "q1", title: "Soru", detail: "rm -rf build")) }
        await waitForQuestion(store)
        #expect(store.current?.detail == "rm -rf build")
        store.answer("q1", with: .allow)
        let response = await task.value
        #expect(response.ok)
        #expect(response.decision == .allow)
        #expect(store.questions.isEmpty)
    }

    @Test func expiryGivesNoDecision() async {
        let store = QuestionStore()
        let response = await store.ask(ActivityRequest(op: .ask, id: "q2", title: "Soru", ttl: 1))
        #expect(response.ok)
        #expect(response.decision == nil)
        #expect(store.questions.isEmpty)
    }

    @Test func cancellationRemovesQuestionWithoutDecision() async {
        let store = QuestionStore()
        let task = Task { await store.ask(ActivityRequest(op: .ask, id: "q3", title: "Soru")) }
        await waitForQuestion(store)
        task.cancel()
        let response = await task.value
        #expect(response.decision == nil)
        while !store.questions.isEmpty { await Task.yield() }
        #expect(store.questions.isEmpty)
    }

    @Test func disabledStoreReturnsNoDecisionImmediately() async {
        let store = QuestionStore()
        store.isEnabled = false
        let response = await store.ask(ActivityRequest(op: .ask, id: "q4", title: "Soru"))
        #expect(response.ok)
        #expect(response.decision == nil)
        #expect(store.questions.isEmpty)
    }

    @Test func rejectsInvalidQuestions() async {
        let store = QuestionStore()
        let long = String(repeating: "x", count: ExternalQuestion.maximumDetailLength + 1)
        #expect(await store.ask(ActivityRequest(op: .ask, id: "q5", title: "Soru", detail: long)).ok == false)
        #expect(await store.ask(ActivityRequest(op: .ask, id: "q6", title: "Soru", ttl: 900)).ok == false)
        #expect(await store.ask(ActivityRequest(op: .ask, title: "Kimliksiz")).ok == false)
    }

    @Test func activityStoreRefusesAsk() {
        let store = ExternalActivityStore()
        #expect(store.handle(ActivityRequest(op: .ask, id: "q7", title: "Soru")).ok == false)
    }
}

struct ClaudePermissionHookTests {
    // Belgedeki örnek girdi (code.claude.com/docs/en/hooks, PermissionRequest).
    static let bashInput = #"{"session_id":"abc123","cwd":"/Users/me/proje","permission_mode":"default","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"rm -rf node_modules","description":"Remove node_modules directory"}}"#

    @Test func parsesBashCommandAndProject() throws {
        let input = try #require(ClaudePermissionHook.parse(Data(Self.bashInput.utf8)))
        #expect(input.toolName == "Bash")
        #expect(input.project == "proje")
        #expect(input.sessionPrefix == "abc123")
        #expect(input.summary == "rm -rf node_modules\n# Remove node_modules directory")
    }

    @Test func filePathsAreShownRelativeToProject() throws {
        let json = #"{"session_id":"s","cwd":"/Users/me/proje","tool_name":"Edit","tool_input":{"file_path":"/Users/me/proje/App/Main.swift","old_string":"a","new_string":"b"}}"#
        let input = try #require(ClaudePermissionHook.parse(Data(json.utf8)))
        #expect(input.summary == "App/Main.swift")
    }

    @Test func mcpToolGetsReadableName() throws {
        #expect(ClaudePermissionHook.displayName(for: "mcp__github__create_issue") == "github › create_issue")
        let json = #"{"session_id":"s","cwd":"/tmp","tool_name":"mcp__github__create_issue","tool_input":{"title":"Hata"}}"#
        let input = try #require(ClaudePermissionHook.parse(Data(json.utf8)))
        #expect(input.summary == #"{"title":"Hata"}"#)
    }

    @Test func missingToolNameMeansNoQuestion() {
        #expect(ClaudePermissionHook.parse(Data(#"{"session_id":"s"}"#.utf8)) == nil)
        #expect(ClaudePermissionHook.parse(Data("bozuk".utf8)) == nil)
    }

    @Test func requestIsAValidQuestion() throws {
        let input = try #require(ClaudePermissionHook.parse(Data(Self.bashInput.utf8)))
        let request = ClaudePermissionHook.request(for: input, timeout: 110, turkish: true)
        #expect(request.op == .ask)
        #expect(request.subtitle == "Bash · proje")
        let question = try ExternalQuestion.validated(from: request)
        #expect(question.id.hasPrefix("claude-perm-abc123-"))
    }

    @Test func outputMatchesDocumentedShape() throws {
        #expect(ClaudePermissionHook.output(for: nil, turkish: true) == nil)
        let allow = try #require(ClaudePermissionHook.output(for: .allow, turkish: true))
        #expect(allow == #"{"hookSpecificOutput":{"decision":{"behavior":"allow"},"hookEventName":"PermissionRequest"}}"#)
        let deny = try #require(ClaudePermissionHook.output(for: .deny, turkish: false))
        let object = try #require(try JSONSerialization.jsonObject(with: Data(deny.utf8)) as? [String: Any])
        let decision = (object["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any]
        #expect(decision?["behavior"] as? String == "deny")
        #expect(decision?["message"] as? String != nil)
        // Kalıcı izin kuralı hiçbir zaman yazılmaz.
        #expect(decision?["updatedPermissions"] == nil)
    }
}

/// Gerçek soket üzerinden: soru sor, yanıtla; istemci giderse soru düşsün.
@MainActor
struct QuestionSocketTests {
    @Test func askOverSocketReturnsUsersDecision() async throws {
        let url = URL(fileURLWithPath: "/tmp/ntest-\(UUID().uuidString.prefix(8)).sock")
        let questions = QuestionStore()
        let server = ActivitySocketServer(socketURL: url) { request in await questions.ask(request) }
        try server.start()
        defer { server.stop() }

        let client = Task.detached {
            try ActivitySocketClient.send(ActivityRequest(op: .ask, id: "sock1", title: "Soru"), socketURL: url, timeout: 10)
        }
        while questions.questions.isEmpty { await Task.yield() }
        questions.answer("sock1", with: .deny)
        let response = try await client.value
        #expect(response.decision == .deny)
    }

    @Test func clientDisconnectCancelsQuestion() async throws {
        let url = URL(fileURLWithPath: "/tmp/ntest-\(UUID().uuidString.prefix(8)).sock")
        let questions = QuestionStore()
        let server = ActivitySocketServer(socketURL: url) { request in await questions.ask(request) }
        try server.start()
        defer { server.stop() }

        // İstemci 1 sn sonra vazgeçip bağlantıyı kapatır (kancanın öldürülmesi gibi).
        let client = Task.detached {
            try? ActivitySocketClient.send(ActivityRequest(op: .ask, id: "sock2", title: "Soru"), socketURL: url, timeout: 1)
        }
        while questions.questions.isEmpty { await Task.yield() }
        _ = await client.value
        let deadline = Date.now.addingTimeInterval(3)
        while !questions.questions.isEmpty, Date.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
        #expect(questions.questions.isEmpty)
    }
}
