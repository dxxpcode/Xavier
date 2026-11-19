import Foundation

/// Coordinates conversations: persistence, context assembly, streaming
/// inference, cancellation, and memory extraction. No SwiftUI dependencies.
@MainActor
final class AssistantOrchestrator: ObservableObject {
    @Published private(set) var conversation: Conversation?
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var isGenerating = false
    @Published var lastError: String?

    let conversationStore: ConversationStore
    let memoryEngine: MemoryEngine
    let modelManager: ModelManager
    private let provider: InferenceProvider
    private let contextBuilder = ContextBuilder()
    private let settings: SettingsStore

    /// Set by the voice engine to speak assistant responses aloud.
    var onAssistantCompleted: ((String) -> Void)?
    /// Called when an exchange fails or produces no reply, so voice can reset.
    var onAssistantFailed: (() -> Void)?

    init(conversationStore: ConversationStore, memoryEngine: MemoryEngine,
         modelManager: ModelManager, provider: InferenceProvider, settings: SettingsStore) {
        self.conversationStore = conversationStore
        self.memoryEngine = memoryEngine
        self.modelManager = modelManager
        self.provider = provider
        self.settings = settings
    }

    // MARK: - Conversation lifecycle

    func loadLatestOrCreate() {
        do {
            if let latest = try conversationStore.latestConversation() {
                load(conversation: latest)
            } else {
                newConversation()
            }
        } catch {
            newConversation()
        }
    }

    func load(conversation: Conversation) {
        cancelGeneration()
        self.conversation = conversation
        messages = (try? conversationStore.messages(forConversation: conversation.id)) ?? []
        lastError = nil
    }

    @discardableResult
    func newConversation() -> Conversation? {
        cancelGeneration()
        do {
            let c = try conversationStore.createConversation()
            conversation = c
            messages = []
            lastError = nil
            return c
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func deleteConversation(id: String) {
        try? conversationStore.deleteConversation(id: id)
        if conversation?.id == id {
            newConversation()
        }
    }

    func setExcludedFromMemory(_ excluded: Bool) {
        guard let id = conversation?.id else { return }
        try? conversationStore.setExcludedFromMemory(id: id, excluded: excluded)
        conversation?.excludedFromMemory = excluded
    }

    // MARK: - Sending

    /// `toConversationID` directs the message to the conversation that was
    /// active when the input began (voice capture may outlive a chat switch).
    func send(text rawText: String, toConversationID: String? = nil) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isGenerating else { return }
        if let toConversationID, toConversationID != conversation?.id,
           let target = try? conversationStore.conversation(id: toConversationID) {
            load(conversation: target)
        }
        if conversation == nil { newConversation() }
        guard let conv = conversation else { return }

        do {
            let userMessage = try conversationStore.appendMessage(conversationID: conv.id, role: .user, content: text)
            messages.append(userMessage)
            if messages.count == 1 {
                try conversationStore.autoTitle(id: conv.id, from: text)
                if var c = conversation { c.title = String(text.prefix(48)); conversation = c }
            }
        } catch {
            lastError = error.localizedDescription
            return
        }
        streamAssistantResponse()
    }

    func regenerate() {
        guard !isGenerating else { return }
        // Remove the last assistant message and regenerate.
        if let last = messages.last, last.role == .assistant {
            try? conversationStore.deleteMessage(id: last.id)
            messages.removeLast()
        }
        guard messages.last?.role == .user else { return }
        streamAssistantResponse()
    }

    func cancelGeneration() {
        provider.cancel()
        isGenerating = false
        if let last = messages.last, last.role == .assistant, !last.isComplete {
            finalize(message: last, content: last.content, interrupted: true)
        }
    }

    private func streamAssistantResponse() {
        guard let conv = conversation else { return }
        let model = modelManager.selectedModel
        guard !model.isEmpty else {
            lastError = InferenceError.noModelSelected.localizedDescription
            appendSystemNote(InferenceError.noModelSelected.localizedDescription)
            onAssistantFailed?()
            return
        }
        isGenerating = true
        lastError = nil

        var assistantMessage: ChatMessage
        do {
            assistantMessage = try conversationStore.appendMessage(conversationID: conv.id, role: .assistant, content: "", isComplete: false)
            messages.append(assistantMessage)
        } catch {
            lastError = error.localizedDescription
            isGenerating = false
            return
        }

        let excluded = conv.excludedFromMemory
        let userText = messages.last(where: { $0.role == .user })?.content ?? ""
        let memories = excluded ? [] : memoryEngine.relevantMemories(for: userText)
        let turns = contextBuilder.buildTurns(messages: messages.filter { $0.id != assistantMessage.id },
                                              memories: memories,
                                              memoryEnabled: settings.automaticMemoryEnabled && !excluded)

        Task { [weak self] in
            guard let self else { return }
            var accumulated = ""
            do {
                for try await delta in provider.streamChat(model: model, messages: turns, interruptible: true) {
                    accumulated += delta
                    self.updateStreaming(id: assistantMessage.id, content: accumulated)
                }
                self.finishExchange(messageID: assistantMessage.id, content: accumulated,
                                    userText: userText, excluded: excluded, conversationID: conv.id)
            } catch InferenceError.cancelled {
                self.finishExchange(messageID: assistantMessage.id, content: accumulated,
                                    userText: userText, excluded: excluded, interrupted: true,
                                    conversationID: conv.id)
            } catch {
                self.failExchange(messageID: assistantMessage.id, error: error)
            }
        }
    }

    private func updateStreaming(id: String, content: String) {
        guard let idx = messages.lastIndex(where: { $0.id == id }) else { return }
        messages[idx].content = content
    }

    private func finishExchange(messageID: String, content: String, userText: String,
                              excluded: Bool, interrupted: Bool = false,
                              conversationID: String) {
        isGenerating = false
        finalize(message: messages.first(where: { $0.id == messageID }), content: content, interrupted: interrupted)
        if !content.isEmpty {
            onAssistantCompleted?(content)
        } else {
            onAssistantFailed?()
        }
        // Memory extraction runs after the exchange completes.
        if !excluded && !content.isEmpty {
            let engine = memoryEngine
            let provider = self.provider
            let model = modelManager.selectedModel
            let convID = conversationID
            Task { [weak self] in
                await engine.extract(fromUserText: userText, assistantText: content,
                                     conversationID: convID, provider: provider, model: model) {
                    (try? self?.conversationStore.isExcludedFromMemory(id: convID)) == false
                }
            }
        }
    }

    private func failExchange(messageID: String, error: Error) {
        isGenerating = false
        let message = error.localizedDescription
        lastError = message
        finalize(message: messages.first(where: { $0.id == messageID }),
                 content: "Something went wrong: \(message)", interrupted: true)
        onAssistantFailed?()
    }

    private func finalize(message: ChatMessage?, content: String, interrupted: Bool) {
        guard var m = message else { return }
        m.content = content
        m.isComplete = true
        try? conversationStore.updateMessage(id: m.id, content: content, isComplete: true)
        if let idx = messages.firstIndex(where: { $0.id == m.id }) {
            messages[idx] = m
        }
    }

    private func appendSystemNote(_ text: String) {
        guard let conv = conversation else { return }
        if let note = try? conversationStore.appendMessage(conversationID: conv.id, role: .system, content: text) {
            messages.append(note)
        }
    }
}
