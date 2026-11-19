import Foundation

/// Tracks the local inference runtime and its installed models.
@MainActor
final class ModelManager: ObservableObject {
    enum RuntimeStatus: Equatable {
        case unknown
        case checking
        case available
        case unavailable
    }

    @Published private(set) var status: RuntimeStatus = .unknown
    @Published private(set) var models: [LocalModel] = []
    @Published var selectedModel: String = ""
    @Published private(set) var pullProgress: (fraction: Double, status: String)? = nil
    @Published var lastError: String?

    private let provider: InferenceProvider
    private let settings: SettingsStore

    init(provider: InferenceProvider, settings: SettingsStore) {
        self.provider = provider
        self.settings = settings
        self.selectedModel = settings.selectedModel
    }

    func refresh() async {
        status = .checking
        if await provider.isAvailable() {
            status = .available
            do {
                models = try await provider.listModels()
                lastError = nil
                if selectedModel.isEmpty, let first = models.first {
                    select(model: first.name)
                }
            } catch {
                models = []
                lastError = error.localizedDescription
            }
        } else {
            status = .unavailable
            models = []
        }
    }

    func select(model: String) {
        selectedModel = model
        settings.selectedModel = model
    }

    func pull(name: String) async {
        guard !name.isEmpty else { return }
        pullProgress = (0, "Starting…")
        do {
            try await provider.pullModel(name: name) { fraction, status in
                Task { @MainActor in self.pullProgress = (fraction, status) }
            }
            pullProgress = nil
            await refresh()
        } catch {
            pullProgress = nil
            lastError = error.localizedDescription
        }
    }

    func remove(name: String) async {
        do {
            try await provider.deleteModel(name: name)
            if selectedModel == name { selectedModel = "" }
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Rough check that the machine can plausibly run the selected model.
    func hardwareNote(for model: LocalModel) -> String? {
        guard let bytes = model.sizeBytes else { return nil }
        let memory = ProcessInfo.processInfo.physicalMemory
        // Rule of thumb: model size should stay well under physical RAM.
        if UInt64(bytes) * 2 > memory {
            return "This model may exceed your Mac's memory. A smaller model is recommended."
        }
        return nil
    }
}
