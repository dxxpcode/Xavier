import Combine
import Foundation

/// Aggregate application state shared across the floating window, menu bar,
/// preferences, and onboarding.
@MainActor
final class AppState: ObservableObject {
    let settings: SettingsStore
    let modelManager: ModelManager
    let orchestrator: AssistantOrchestrator
    let voiceSession: VoiceSession
    let memoryEngine: MemoryEngine
    let conversationStore: ConversationStore
    let provider: InferenceProvider

    @Published var isPanelVisible = false
    @Published var showHistory = false

    /// The most recent exchange, surfaced on the orb as a transient card.
    struct Exchange: Equatable {
        var question: String
        var answer: String?
    }
    @Published var lastExchange: Exchange?

    private var cancellables = Set<AnyCancellable>()

    /// Set by AppDelegate; opens the preferences window.
    var onOpenPreferences: (() -> Void)?

    init() {
        let settings = SettingsStore.shared
        let database: Database
        do {
            database = try Database()
        } catch {
            fatalError("Could not open Xavier database: \(error.localizedDescription)")
        }
        let conversationStore = ConversationStore(db: database)
        let memoryStore = MemoryStore(db: database)
        let memoryEngine = MemoryEngine(store: memoryStore, settings: settings)
        let baseURL = URL(string: settings.ollamaBaseURL) ?? URL(string: "http://localhost:11434")!
        let provider = OllamaProvider(baseURL: baseURL)
        let modelManager = ModelManager(provider: provider, settings: settings)
        let orchestrator = AssistantOrchestrator(conversationStore: conversationStore,
                                                 memoryEngine: memoryEngine,
                                                 modelManager: modelManager,
                                                 provider: provider,
                                                 settings: settings)
        let voice = VoiceSession(settings: settings)

        self.settings = settings
        self.provider = provider
        self.modelManager = modelManager
        self.orchestrator = orchestrator
        self.voiceSession = voice
        self.memoryEngine = memoryEngine
        self.conversationStore = conversationStore

        // Wire voice → orchestrator → voice.
        voice.conversationProvider = { [weak orchestrator] in
            orchestrator?.conversation?.id
        }
        voice.onTranscript = { [weak self, weak orchestrator, weak voice] text, conversationID in
            voice?.setProcessing()
            self?.lastExchange = Exchange(question: text, answer: nil)
            orchestrator?.send(text: text, toConversationID: conversationID)
            voice?.lastExchangeConversationID = orchestrator?.conversation?.id
        }
        orchestrator.onAssistantCompleted = { [weak self, weak voice, weak orchestrator] response in
            // Track the exchange's conversation for voice follow-ups —
            // typed replies trigger them too, so this must update here.
            voice?.lastExchangeConversationID = orchestrator?.conversation?.id
            let question = self?.lastExchange?.question
                ?? orchestrator?.messages.last(where: { $0.role == .user })?.content
                ?? ""
            self?.lastExchange = Exchange(question: question, answer: response)
            voice?.speak(response)
        }
        orchestrator.onAssistantFailed = { [weak voice] in
            voice?.setIdle()
        }

        // Endpoint changes take effect immediately, not on restart.
        settings.$ollamaBaseURL.dropFirst().sink { [weak provider, weak modelManager] value in
            guard let url = URL(string: value) else { return }
            provider?.baseURL = url
            Task { await modelManager?.refresh() }
        }.store(in: &cancellables)
    }

    func start() {
        orchestrator.loadLatestOrCreate()
        Task { await modelManager.refresh() }
    }

    func openPreferences() { onOpenPreferences?() }

    /// Typed input path (orb type mode): records the exchange for the
    /// answer card, then sends through the normal pipeline.
    func sendTyped(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lastExchange = Exchange(question: trimmed, answer: nil)
        orchestrator.send(text: trimmed)
    }
}
