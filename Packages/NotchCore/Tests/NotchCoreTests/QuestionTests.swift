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

    @Test func dismissClosesMatchingQuestionsWithoutDecision() async {
        let store = QuestionStore()
        var reasons: [QuestionStore.Resolution] = []
        store.onResolved = { _, _, reason in reasons.append(reason) }
        let first = Task { await store.ask(ActivityRequest(op: .ask, id: "claude-perm-abc-1", title: "Bir")) }
        let second = Task { await store.ask(ActivityRequest(op: .ask, id: "claude-perm-abc-2", title: "İki")) }
        let other = Task { await store.ask(ActivityRequest(op: .ask, id: "claude-perm-xyz-1", title: "Başka")) }
        while store.questions.count < 3 { await Task.yield() }

        let exact = store.dismiss(ActivityRequest(op: .dismiss, id: "claude-perm-abc-1"))
        #expect(exact.dismissed == 1)
        let prefix = store.dismiss(ActivityRequest(op: .dismiss, id: "claude-perm-abc-*"))
        #expect(prefix.dismissed == 1)
        #expect(await first.value.decision == nil)
        #expect(await second.value.decision == nil)
        #expect(store.questions.map(\.id) == ["claude-perm-xyz-1"])
        #expect(reasons == [.dismissed, .dismissed])

        // Boş ya da yalnız "*" hepsini kapatamaz.
        #expect(store.dismiss(ActivityRequest(op: .dismiss, id: "*")).ok == false)
        #expect(store.dismiss(ActivityRequest(op: .dismiss)).ok == false)
        store.answer("claude-perm-xyz-1", with: .deny)
        #expect(await other.value.decision == .deny)
    }

    @Test func choiceQuestionReturnsSelection() async {
        let store = QuestionStore()
        let single = Task { await store.ask(ActivityRequest(op: .ask, id: "c1", title: "Renk", choices: ["Mavi", "Kırmızı"])) }
        await waitForQuestion(store)
        store.answer("c1", selection: [5])          // aralık dışı: yok sayılır
        store.answer("c1", selection: [0, 1])       // tek seçimli: yok sayılır
        store.answer("c1", with: .allow)            // onay düğmesi değil ama yine de yanıt: seçim yok
        let first = await single.value
        #expect(first.selection == nil)

        let multi = Task { await store.ask(ActivityRequest(op: .ask, id: "c2", title: "Hangileri", choices: ["A", "B", "C"], multiple: true)) }
        await waitForQuestion(store)
        store.answer("c2", selection: [2, 0, 2])
        #expect(await multi.value.selection == [0, 2])
    }

    @Test func questionKindsCanBeTurnedOffSeparately() async {
        let store = QuestionStore()
        store.acceptsApprovals = false
        // Onay sorusu kapalı: hemen yanıtsız döner, notch'ta görünmez.
        let approval = await store.ask(ActivityRequest(op: .ask, id: "k1", title: "İzin"))
        #expect(approval.ok && approval.decision == nil && store.questions.isEmpty)
        // Seçenekli soru açık: bekler.
        let choice = Task { await store.ask(ActivityRequest(op: .ask, id: "k2", title: "Seç", choices: ["A", "B"])) }
        await waitForQuestion(store)
        #expect(store.accepts(store.questions[0]))
        store.answer("k2", selection: [1])
        #expect(await choice.value.selection == [1])
    }

    @Test func choiceValidation() {
        let tooMany = ActivityRequest(op: .ask, id: "v1", title: "S", choices: (1...7).map(String.init))
        #expect(throws: ExternalActivity.ValidationError.self) { try ExternalQuestion.validated(from: tooMany) }
        let mismatch = ActivityRequest(op: .ask, id: "v2", title: "S", choices: ["A", "B"], choiceDetails: ["a"])
        #expect(throws: ExternalActivity.ValidationError.self) { try ExternalQuestion.validated(from: mismatch) }
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
    /// Kanca betiği parmak izini `plutil` + `shasum` ile hesaplar; Swift'le birebir aynı olmalı, yoksa
    /// Claude'da onaylanan istek notch'tan düşmez.
    @Test func fingerprintMatchesTheHookScriptPipeline() throws {
        let command = "echo \"çalış\" && ls -la 'ö dosya'\n"
        let object: [String: Any] = ["tool_name": "Bash", "session_id": "8f1c2d3e-aaaa", "tool_input": ["command": command]]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        let input = try #require(ClaudePermissionHook.parse(Data(json.utf8)))
        // JSON stdin'den, gerçek kancadaki gibi (argüman olarak verilince Process Unicode'u NFD'ye çeviriyor).
        let script = #"input=$(cat); key=$(printf '%s' "$input" | /usr/bin/plutil -extract tool_input.command raw -o - - 2>/dev/null); printf '%s\n%s' Bash "$key" | shasum -a 256 | cut -c1-10"#
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script]
        let pipe = Pipe()
        let stdin = Pipe()
        process.standardOutput = pipe
        process.standardInput = stdin
        try process.run()
        stdin.fileHandleForWriting.write(Data(json.utf8))
        try stdin.fileHandleForWriting.close()
        process.waitUntilExit()
        let shell = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(shell == input.fingerprint)
        #expect(ClaudePermissionHook.questionID(sessionPrefix: input.sessionPrefix, fingerprint: input.fingerprint, suffix: "z")
                == "claude-perm-8f1c2d3e-\(input.fingerprint)-z")
        #expect(ClaudePermissionHook.questionID(sessionPrefix: "", fingerprint: "f").hasPrefix("claude-perm-x-f-"))
    }

    @Test func askUserQuestionBecomesChoiceRequestsAndAnswers() throws {
        let json = #"{"tool_name":"AskUserQuestion","session_id":"abc","cwd":"/tmp/proje","tool_input":{"questions":[{"question":"Hangi renk?","header":"Renk","multiSelect":false,"options":[{"label":"Mavi","description":"Serin"},{"label":"Kırmızı","description":"Sıcak"}]},{"question":"Hangileri?","header":"Çoklu","multiSelect":true,"options":[{"label":"A"},{"label":"B"},{"label":"C"}]}]}}"#
        let input = try #require(ClaudePermissionHook.parse(Data(json.utf8)))
        #expect(input.choiceQuestions.count == 2)
        let requests = ClaudePermissionHook.choiceRequests(for: input, timeout: 100, language: .english)
        #expect(requests.map(\.request.choices) == [["Mavi", "Kırmızı"], ["A", "B", "C"]])
        #expect(requests[1].request.multiple == true)
        #expect(requests[0].request.title == "Claude is asking (1/2)")
        // Aynı parmak izi önekini paylaşırlar: Claude'da yanıtlanınca PostToolUse ikisini birden düşürür.
        let prefix = "claude-perm-abc-\(input.fingerprint)-"
        #expect(requests.allSatisfy { $0.request.id?.hasPrefix(prefix) == true })
        #expect(Set(requests.compactMap(\.request.id)).count == 2)
        for (_, request) in requests { _ = try ExternalQuestion.validated(from: request) }

        let output = try #require(ClaudePermissionHook.answerOutput(answers: ["Hangi renk?": "Mavi", "Hangileri?": "A, C"],
                                                                     toolInputJSON: input.toolInputJSON))
        let decoded = try #require(try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
        let decision = try #require((decoded["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any])
        #expect(decision["behavior"] as? String == "allow")
        #expect(decision["updatedPermissions"] == nil)
        let updated = try #require(decision["updatedInput"] as? [String: Any])
        #expect((updated["questions"] as? [Any])?.count == 2)
        #expect(updated["answers"] as? [String: String] == ["Hangi renk?": "Mavi", "Hangileri?": "A, C"])
    }

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
        let request = ClaudePermissionHook.request(for: input, timeout: 110, language: .turkish)
        #expect(request.op == .ask)
        #expect(request.subtitle == "Bash · proje")
        let question = try ExternalQuestion.validated(from: request)
        #expect(question.id.hasPrefix("claude-perm-abc123-"))
    }

    @Test func outputMatchesDocumentedShape() throws {
        #expect(ClaudePermissionHook.output(for: nil, language: .turkish) == nil)
        let allow = try #require(ClaudePermissionHook.output(for: .allow, language: .turkish))
        #expect(allow == #"{"hookSpecificOutput":{"decision":{"behavior":"allow"},"hookEventName":"PermissionRequest"}}"#)
        let deny = try #require(ClaudePermissionHook.output(for: .deny, language: .english))
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
