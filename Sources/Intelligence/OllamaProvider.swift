import Foundation

/// Ollama local runtime integration (default: http://localhost:11434).
/// All inference runs on the local machine; no conversation data leaves the device.
final class OllamaProvider: InferenceProvider, @unchecked Sendable {
    let displayName = "Ollama"

    var baseURL: URL
    private let session: URLSession
    nonisolated(unsafe) private var streamTasks: [UUID: (task: Task<Void, Never>, interruptible: Bool)] = [:]
    private let streamTasksLock = NSLock()

    nonisolated private func addStreamTask(_ task: Task<Void, Never>, interruptible: Bool) -> UUID {
        let id = UUID()
        streamTasksLock.lock()
        streamTasks[id] = (task, interruptible)
        streamTasksLock.unlock()
        return id
    }

    nonisolated private func removeStreamTask(_ id: UUID) {
        streamTasksLock.lock()
        streamTasks.removeValue(forKey: id)
        streamTasksLock.unlock()
    }

    init(baseURL: URL = URL(string: "http://localhost:11434")!) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 600
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    // MARK: Availability

    func isAvailable() async -> Bool {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/version"))
        req.timeoutInterval = 3
        do {
            let (_, resp) = try await session.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: Models

    struct TagsResponse: Decodable {
        struct Model: Decodable {
            let name: String
            let size: Int64?
            let details: Details?
            struct Details: Decodable {
                let parameter_size: String?
                let family: String?
            }
        }
        let models: [Model]
    }

    func listModels() async throws -> [LocalModel] {
        let req = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        let (data, resp) = try await session.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw InferenceError.runtimeUnavailable("Ollama is not reachable at \(baseURL.host ?? "localhost").")
        }
        return try JSONDecoder().decode(TagsResponse.self, from: data).models.map {
            LocalModel(id: $0.name, name: $0.name, sizeBytes: $0.size,
                       parameterSize: $0.details?.parameter_size, family: $0.details?.family)
        }
    }

    func pullModel(name: String, onProgress: @Sendable @escaping (Double, String) -> Void) async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/pull"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["name": name, "stream": true])
        req.timeoutInterval = 3600

        let (bytes, resp) = try await session.bytes(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw InferenceError.requestFailed("Model download failed for \(name).")
        }
        for try await line in bytes.lines {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
            let status = obj["status"] as? String ?? ""
            let total = (obj["total"] as? Double) ?? 0
            let completed = (obj["completed"] as? Double) ?? 0
            onProgress(total > 0 ? completed / total : 0, status)
        }
    }

    func deleteModel(name: String) async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/delete"))
        req.httpMethod = "DELETE"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["name": name])
        let (_, resp) = try await session.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw InferenceError.requestFailed("Could not remove model \(name).")
        }
    }

    // MARK: Chat

    func streamChat(model: String, messages: [ChatTurn], interruptible: Bool = true) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            var req = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = [
                "model": model,
                "stream": true,
                "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
            ]
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)

            let task = Task {
                defer { continuation.finish() }
                do {
                    let (bytes, resp) = try await session.bytes(for: req)
                    if let code = (resp as? HTTPURLResponse)?.statusCode, code != 200 {
                        var errorBody = ""
                        for try await line in bytes.lines { errorBody += line }
                        let detail = (try? JSONSerialization.jsonObject(with: Data(errorBody.utf8)) as? [String: Any])?["error"] as? String
                        continuation.yield(with: .failure(InferenceError.requestFailed(detail ?? "Ollama request failed (\(code)).")))
                        return
                    }
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
                        if let message = obj["message"] as? [String: Any],
                           let content = message["content"] as? String, !content.isEmpty {
                            continuation.yield(content)
                        }
                        if (obj["done"] as? Bool) == true { break }
                    }
                } catch is CancellationError {
                    continuation.yield(with: .failure(InferenceError.cancelled))
                } catch {
                    if (error as NSError).code == NSURLErrorCancelled {
                        continuation.yield(with: .failure(InferenceError.cancelled))
                    } else {
                        continuation.yield(with: .failure(error))
                    }
                }
            }

            let taskID = self.addStreamTask(task, interruptible: interruptible)
            continuation.onTermination = { _ in
                task.cancel()
                self.removeStreamTask(taskID)
            }
        }
    }

    func cancel() {
        streamTasksLock.lock()
        let tasks = streamTasks.values.filter(\.interruptible).map(\.task)
        streamTasksLock.unlock()
        tasks.forEach { $0.cancel() }
    }
}
