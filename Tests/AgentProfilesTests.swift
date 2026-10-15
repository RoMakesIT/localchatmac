import Foundation

// Intercept requests in-process: no Ollama, memory service, or external search is contacted.
final class MockOllamaProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var requests: [OllamaChatRequest] = []
    private static var replies: [String] = []
    static var statusCode = 200
    private var work: DispatchWorkItem?

    static func reset(status: Int = 200, replies: [String] = []) {
        lock.lock()
        defer { lock.unlock() }
        requests = []
        statusCode = status
        Self.replies = replies
    }

    static func capturedRequests() -> [OllamaChatRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(buffer, count: count)
            }
        }
        Self.lock.lock()
        let decoded = try? JSONDecoder().decode(OllamaChatRequest.self, from: body)
        if let decoded {
            Self.requests.append(decoded)
        }
        let status = Self.statusCode
        let customReply = request.url?.path == "/api/chat" && !Self.replies.isEmpty ? Self.replies.removeFirst() : nil
        let structured = decoded?.format != nil
        Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        let pending = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            let json: String
            switch self.request.url!.path {
            case "/api/tags": json = #"{"models":[{"name":"tool-model"}]}"#
            case "/api/show": json = #"{"capabilities":["completion","tools","vision"]}"#
            default:
                if let customReply { json = customReply }
                else if structured {
                    json = #"{"message":{"role":"assistant","content":"{\"action\":\"answer\",\"answer\":\"Verified mock answer\"}"},"done":true}"#
                } else { json = #"{"message":{"role":"assistant","content":"Verified mock answer"},"done":true}"# }
            }
            self.client?.urlProtocol(self, didLoad: Data(json.utf8))
            self.client?.urlProtocolDidFinishLoading(self)
        }
        work = pending
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.15, execute: pending)
    }

    override func stopLoading() { work?.cancel() }
}

@main
struct AgentProfilesTests {
    @MainActor
    static func main() async throws {
        try await PersonalTaxRecordsTests.run()
        try await TaxRecordsTests.run()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lantern-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let state = AppState(storageDirectory: root, startsServices: false)
        let initialChatID = state.selectedConversationID!
        assert(state.assistantMode == .chat && !state.verificationEnabled)
        assert(!state.webSearchEnabled && state.memoryEnabled)
        assert(state.activeToolNames.contains("plan_daily_schedule"))
        assert(!state.activeToolNames.contains("analyze_finance_ledger"))

        state.systemPrompt = "Personal chat instructions"
        state.systemPromptPreset = .custom
        state.model = "chat-model"
        state.memoryEnabled = false
        let chatProfile = state.agentConfiguration
        state.selectAssistantMode(.code)
        assert(state.systemPromptPreset == .precise && state.verificationEnabled)
        assert(state.memoryEnabled && !state.webSearchEnabled)
        assert(!state.activeToolNames.contains("analyze_finance_ledger"))
        assert(!state.activeToolNames.contains("plan_daily_schedule"))
        state.model = "code-model"
        state.webSearchEnabled = true
        let codeProfile = state.agentConfiguration
        state.selectAssistantMode(.finance)
        assert(state.activeToolNames.contains("analyze_finance_ledger"))
        assert(state.verificationEnabled && state.systemPromptPreset == .precise)
        state.selectAssistantMode(.chat)
        assert(state.agentConfiguration == chatProfile)
        state.selectAssistantMode(.code)
        assert(state.agentConfiguration == codeProfile)

        state.newChat()
        let codeChatID = state.selectedConversationID!
        state.selectAssistantMode(.finance)
        state.newChat()
        let financeChatID = state.selectedConversationID!
        state.selectConversation(codeChatID)
        // The earlier conversation was explicitly switched to Finance before creating this one.
        assert(state.assistantMode == .finance)
        state.selectConversation(initialChatID)
        assert(state.assistantMode == .code)
        state.selectAssistantMode(.chat)
        state.selectConversation(financeChatID)
        assert(state.assistantMode == .finance)
        state.selectConversation(initialChatID)
        assert(state.assistantMode == .chat && state.agentConfiguration == chatProfile)

        let reopened = AppState(storageDirectory: root, startsServices: false)
        assert(reopened.agentConfiguration == chatProfile)
        reopened.selectAssistantMode(.code)
        assert(reopened.agentConfiguration == codeProfile)
        reopened.resetAgentConfiguration()
        assert(reopened.systemPromptPreset == .precise && !reopened.webSearchEnabled)
        reopened.selectAssistantMode(.chat)
        assert(reopened.agentConfiguration == chatProfile)

        // Project selection must never change the mode stored on the previous conversation.
        let previousID = reopened.selectedConversationID!
        let project = ChatProject(name: "Finance project", preferredAssistantMode: "finance")
        reopened.projects.append(project)
        reopened.selectProject(project.id)
        assert(reopened.assistantMode == .finance)
        assert(reopened.conversations.first(where: { $0.id == previousID })?.assistantMode == .chat)
        reopened.selectConversation(previousID)
        assert(reopened.assistantMode == .chat)

        // Remove new fields to exercise decoding and migration of an existing installation.
        reopened.saveAgentSettings()
        let stateURL = root.appendingPathComponent("state.json")
        var legacy = try JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as! [String: Any]
        legacy.removeValue(forKey: "agentConfigurations")
        var threads = legacy["conversations"] as! [[String: Any]]
        for index in threads.indices { threads[index].removeValue(forKey: "assistantMode") }
        legacy["conversations"] = threads
        try JSONSerialization.data(withJSONObject: legacy).write(to: stateURL)
        let migrated = AppState(storageDirectory: root, startsServices: false)
        assert(migrated.agentConfiguration == chatProfile)
        migrated.selectAssistantMode(.finance)
        assert(migrated.systemPromptPreset == .precise && migrated.verificationEnabled)
        migrated.selectAssistantMode(.chat)
        assert(migrated.agentConfiguration == chatProfile)
        print("PASS: defaults, customized profiles, chat/project switching, persistence, reset, legacy migration")

        URLCache.shared = URLCache(memoryCapacity: 0, diskCapacity: 0, diskPath: nil)
        assert(URLProtocol.registerClass(MockOllamaProtocol.self))
        defer { URLProtocol.unregisterClass(MockOllamaProtocol.self) }
        let networkState = AppState(storageDirectory: root.appendingPathComponent("network"), startsServices: false)
        networkState.financeEntries = [FinanceEntry(name: "Salary", amountCents: 500_000, type: .income, category: .payIncome, frequency: .monthly)]
        networkState.memoryEnabled = false
        networkState.input = "Explain a simple greeting"
        MockOllamaProtocol.reset()
        networkState.startSending()
        try await Task.sleep(for: .milliseconds(40))
        assert(networkState.isSending && networkState.responseStartedAt != nil)
        assert(networkState.activityLabel == "Thinking…")
        let sendingID = networkState.selectedConversationID
        networkState.selectAssistantMode(.finance)
        networkState.newChat()
        assert(networkState.assistantMode == .chat && networkState.selectedConversationID == sendingID)
        try await waitForReply(networkState)
        assert(networkState.responseStartedAt == nil && networkState.statusText == "Ready")
        assert(networkState.currentMessages.last?.content == "Verified mock answer")
        let chatRequest = MockOllamaProtocol.capturedRequests().last!
        assert(chatRequest.options.temperature == 0.5)
        assert(!chatRequest.messages[0].content!.contains("LOCAL FINANCE LEDGER"))
        assert(!chatRequest.messages[0].content!.contains("call analyze_finance_ledger"))

        await networkState.refreshAvailableModels()
        assert(networkState.selectedModelSupportsTools && networkState.selectedModelSupportsVision)
        networkState.selectAssistantMode(.finance)
        networkState.memoryEnabled = false
        networkState.input = "Optimize my finances"
        MockOllamaProtocol.reset()
        await networkState.sendMessage()
        assert(networkState.currentMessages.last?.content == "Verified mock answer")
        let financeRequests = MockOllamaProtocol.capturedRequests()
        assert(financeRequests.count == 2, "Finance should run a verification pass")
        assert(financeRequests[0].options.temperature == 0.1)
        let financeTools = financeRequests[0].tools!.map { $0.function.name }
        assert(financeTools.contains("analyze_finance_ledger"))
        assert(!financeTools.contains("plan_daily_schedule"))
        assert((financeRequests[0].messages.map { $0.content ?? "" }.joined(separator: "\n")).contains("LOCAL FINANCE LEDGER"))
        assert((financeRequests[0].messages.map { $0.content ?? "" }.joined(separator: "\n")).contains("Salary"))
        assert(!networkState.isSending && networkState.responseStartedAt == nil)

        networkState.input = "Analyze a scenario"
        MockOllamaProtocol.reset(status: 500)
        await networkState.sendMessage()
        assert(networkState.statusText == "Request failed")
        assert(!networkState.isSending && networkState.responseStartedAt == nil)

        networkState.input = "Analyze another scenario"
        MockOllamaProtocol.reset()
        networkState.startSending()
        try await Task.sleep(for: .milliseconds(40))
        assert(networkState.isSending)
        networkState.cancelSending()
        try await waitForReply(networkState)
        assert(networkState.statusText == "Cancelled" && networkState.responseStartedAt == nil)
        networkState.selectAssistantMode(.chat)
        networkState.input = "best way to review email"
        await networkState.sendMessage()
        assert(networkState.statusText == "Needs clarification")
        assert(!networkState.isSending && networkState.responseStartedAt == nil)
        networkState.selectAssistantMode(.code)
        networkState.memoryEnabled = false
        networkState.input = "Debug this function"
        MockOllamaProtocol.reset()
        await networkState.sendMessage()
        let codeRequest = MockOllamaProtocol.capturedRequests().first!
        assert(codeRequest.options.temperature == 0.2)
        assert(!codeRequest.tools!.contains(where: { $0.function.name == "analyze_finance_ledger" }))
        assert(!codeRequest.messages[0].content!.contains("LOCAL FINANCE LEDGER"))
        networkState.selectAssistantMode(.tax)
        var taxRecord = TaxYearRecord()
        taxRecord.entityName = "Test Tax Entity"
        taxRecord.incomeCents = 100000
        taxRecord.expenseCents = 25000
        try networkState.saveTaxRecord(taxRecord)
        networkState.input = "Review my current tax figures"
        MockOllamaProtocol.reset()
        await networkState.sendMessage()
        let taxRequests = MockOllamaProtocol.capturedRequests()
        assert(taxRequests.count == 2)
        assert(taxRequests[0].options.temperature == 0.1)
        assert(taxRequests[0].tools!.contains(where: { $0.function.name == "analyze_tax_records" }))
        assert(!taxRequests[0].tools!.contains(where: { $0.function.name == "analyze_finance_ledger" }))
        assert((taxRequests[0].messages.map { $0.content ?? "" }.joined(separator: "\n")).contains("Test Tax Entity"))
        assert((taxRequests[0].messages.map { $0.content ?? "" }.joined(separator: "\n")).contains("USD 750.00"))
        assert(!(taxRequests[0].messages.map { $0.content ?? "" }.joined(separator: "\n")).contains("LOCAL FINANCE LEDGER"))
        networkState.model = "gemma-without-tools"
        networkState.input = "Review the same tax record without native tools"
        MockOllamaProtocol.reset()
        await networkState.sendMessage()
        let noToolRequest = MockOllamaProtocol.capturedRequests().first!
        assert(noToolRequest.tools == nil)
        assert((noToolRequest.messages.map { $0.content ?? "" }.joined(separator: "\n")).contains("USD 750.00"))
        var personalRecord = PersonalTaxYearRecord()
        personalRecord.name = "Personal request test"
        personalRecord.year = 2026
        personalRecord.throughDate = "2026-12-31"
        personalRecord.filingStatus = .single
        var wages = WageRecord()
        wages.employer = "Example Employer"
        wages.wagesCents = 100000
        wages.federalWithholdingCents = 10000
        personalRecord.wages = [wages]
        personalRecord.otherIncomeCents = 0
        personalRecord.federalEstimatedPaymentsCents = 0
        personalRecord.stateEstimatedPaymentsCents = 0
        try networkState.savePersonalTaxRecord(personalRecord)
        networkState.input = "Review my personal wages and business links"
        MockOllamaProtocol.reset()
        await networkState.sendMessage()
        let personalRequest = MockOllamaProtocol.capturedRequests().first!
        assert(personalRequest.tools == nil)
        assert((personalRequest.messages.map { $0.content ?? "" }.joined(separator: "\n")).contains("Example Employer"))
        assert((personalRequest.messages.map { $0.content ?? "" }.joined(separator: "\n")).contains("federal wage withholding: USD 100.00"))
        assert(!(personalRequest.messages.map { $0.content ?? "" }.joined(separator: "\n")).contains("Test Tax Entity"))
        assert(!(personalRequest.messages.map { $0.content ?? "" }.joined(separator: "\n")).contains("LOCAL FINANCE LEDGER"))
        assert(MockOllamaProtocol.capturedRequests().count == 2)
        print("PASS: personal request wages and withholding, unlinked-business isolation, no-native-tool context and verification")
        print("PASS: Tax request scope, deterministic figures with and without native model tools, verification")
        print("PASS: capability discovery, request tools, finance knowledge, verification, activity lifecycle, failure, cancellation, clarification")
        try await HarnessReliabilityTests.run()
    }

    @MainActor
    static func waitForReply(_ state: AppState) async throws {
        for _ in 0..<100 {
            if !state.isSending { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        fatalError("Mock response did not complete")
    }
}
