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

        // Wire voice → orchestrator → voice.
        voice.conversationProvider = { [weak orchestrator] in
            orchestrator?.conversation?.id
        }
        voice.onTranscript = { [weak orchestrator, weak voice] text, conversationID in
            voice?.setProcessing()
            orchestrator?.send(text: text, toConversationID: conversationID)
            voice?.lastExchangeConversationID = orchestrator?.conversation?.id
        }
        orchestrator.onAssistantCompleted = { [weak voice] response in
            voice?.speak(response)
        }
        orchestrator.onAssistantFailed = { [weak voice] in
            voice?.setIdle()
        }

        self.settings = settings
        self.provider = provider
        self.modelManager = modelManager
        self.orchestrator = orchestrator
        self.voiceSession = voice
        self.memoryEngine = memoryEngine
        self.conversationStore = conversationStore
    }

    func start() {
        orchestrator.loadLatestOrCreate()
        Task { await modelManager.refresh() }
    }

    func openPreferences() { onOpenPreferences?() }
}
