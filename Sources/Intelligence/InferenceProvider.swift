import Foundation

struct ChatTurn {
    let role: MessageRole
    let content: String
}

struct LocalModel: Identifiable, Hashable {
    let id: String          // e.g. "llama3.2:latest"
    let name: String
    let sizeBytes: Int64?
    let parameterSize: String?
    let family: String?

    var sizeDescription: String {
        guard let sizeBytes else { return "—" }
        return ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

enum InferenceError: LocalizedError {
    case runtimeUnavailable(String)
    case noModelSelected
    case requestFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .runtimeUnavailable(let s): return s
        case .noModelSelected: return "No local model selected. Choose one in Preferences → AI Models."
        case .requestFailed(let s): return s
        case .cancelled: return "Cancelled."
        }
    }
}

/// Abstraction over local inference runtimes. Conformers must keep all
/// processing on-device / on the local machine (e.g. Ollama, MLX, llama.cpp).
protocol InferenceProvider: AnyObject, Sendable {
    var displayName: String { get }
    func isAvailable() async -> Bool
    func listModels() async throws -> [LocalModel]
    func pullModel(name: String, onProgress: @Sendable @escaping (Double, String) -> Void) async throws
    func deleteModel(name: String) async throws
    /// Streams generated text deltas.
    func streamChat(model: String, messages: [ChatTurn]) -> AsyncThrowingStream<String, Error>
    func cancel()
}
