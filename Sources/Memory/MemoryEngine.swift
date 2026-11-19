import Foundation

/// Extraction, deduplication and retrieval of persistent personal memories.
/// All processing is local: deterministic rules plus optional local-model extraction.
@MainActor
final class MemoryEngine: ObservableObject {
    @Published private(set) var memories: [MemoryItem] = []

    private let store: MemoryStore
    private let settings: SettingsStore

    init(store: MemoryStore, settings: SettingsStore) {
        self.store = store
        self.settings = settings
        reload()
    }

    func reload() {
        memories = (try? store.all()) ?? []
    }

    func update(id: String, content: String, category: MemoryCategory) {
        try? store.update(id: id, content: content, category: category)
        reload()
    }

    func delete(id: String) {
        try? store.delete(id: id)
        reload()
    }

    func deleteAll() {
        try? store.deleteAll()
        reload()
    }

    func search(_ query: String) -> [MemoryItem] {
        (try? store.search(query)) ?? []
    }

    // MARK: - Sensitive data filter

    private static let sensitivePatterns: [String] = [
        #"(?i)\b(password|passwd|passphrase)\b"#,
        #"(?i)\b(api[_-]?key|secret|token)\s*[:=]"#,
        #"(?i)\b(sk|pk|xox[bap]|ghp|gho|sbp)_[A-Za-z0-9_\-]+"#,
        #"\b\d{4}[ -]?\d{4}[ -]?\d{4}[ -]?\d{4}\b"#,          // card numbers
        #"(?i)\b(ssn|social security)\b"#,
        #"(?i)\b(iban|swift|routing number)\b"#,
    ]

    private static let sensitiveRegexes: [NSRegularExpression] = sensitivePatterns.compactMap {
        try? NSRegularExpression(pattern: $0)
    }

    static func isSensitive(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return sensitiveRegexes.contains { $0.firstMatch(in: text, range: range) != nil }
    }

    // MARK: - Extraction

    /// Extracts memory candidates from a finished exchange. Runs deterministic
    /// rules for explicit user statements plus a local-model pass for subtler facts.
    /// `allowed` is re-evaluated right before persisting so a mid-extraction
    /// opt-out (memory toggle off, or conversation excluded) blocks pending writes.
    func extract(fromUserText userText: String, assistantText: String, conversationID: String,
                 provider: InferenceProvider?, model: String,
                 allowed: @escaping () -> Bool = { true }) async {
        guard settings.automaticMemoryEnabled, allowed() else { return }

        var candidates: [(content: String, category: MemoryCategory)] = []

        // Explicit patterns — deterministic, high confidence.
        let lowered = userText.lowercased()
        let explicitTriggers = ["remember that ", "remember this", "don't forget", "do not forget"]
        if explicitTriggers.contains(where: { lowered.contains($0) }) {
            candidates.append((userText, .instruction))
        }
        if lowered.contains("my name is ") {
            candidates.append((userText, .fact))
        }
        if lowered.contains("i prefer ") || lowered.contains("i like ") || lowered.contains("i hate ") {
            candidates.append((userText, .preference))
        }
        if lowered.contains("i'm working on ") || lowered.contains("i am working on ") || lowered.contains("my project") {
            candidates.append((userText, .project))
        }

        // Local-model extraction for subtler facts.
        if let provider, !model.isEmpty, await provider.isAvailable() {
            let extractPrompt = """
            Extract durable facts about the USER from this exchange that would help future \
            conversations — preferences, projects, work context, goals, recurring instructions. \
            Reply with a JSON array of objects with "content" (one sentence) and "category" \
            (one of: Preference, Project, Work, Fact, Instruction, Goal, Recurring). \
            Reply ONLY with the JSON array, or [] if nothing is worth remembering. \
            Do not include credentials, secrets, or sensitive data.

            USER: \(userText)
            ASSISTANT: \(assistantText)
            """
            let turns = [ChatTurn(role: .user, content: extractPrompt)]
            var reply = ""
            do {
                for try await delta in provider.streamChat(model: model, messages: turns) {
                    reply += delta
                }
            } catch {
                // Extraction is best-effort.
            }
            if let parsed = parseExtraction(reply) {
                candidates.append(contentsOf: parsed)
            }
        }

        guard settings.automaticMemoryEnabled, allowed() else { return }
        for (content, category) in candidates {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count > 4, trimmed.count < 500 else { continue }
            guard !Self.isSensitive(trimmed) else { continue }
            upsert(content: trimmed, category: category, sourceConversationID: conversationID)
        }
    }

    private func parseExtraction(_ text: String) -> [(String, MemoryCategory)]? {
        guard let start = text.firstIndex(of: "["), let end = text.lastIndex(of: "]") else { return nil }
        let json = String(text[start...end])
        guard let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else { return nil }
        return arr.compactMap { obj in
            guard let content = obj["content"], !content.isEmpty else { return nil }
            let cat = MemoryCategory(rawValue: obj["category"] ?? "") ?? .fact
            return (content, cat)
        }
    }

    /// Dedupes on normalized text; bumps relevance on near-duplicates.
    private func upsert(content: String, category: MemoryCategory, sourceConversationID: String) {
        let normalized = MemoryItem.normalize(content)
        for existing in memories {
            if existing.normalized == normalized {
                try? store.bumpRelevance(id: existing.id)
                reload()
                return
            }
            // Substring overlap → treat as a duplicate unless meaningfully longer.
            if !normalized.isEmpty,
               (existing.normalized.contains(normalized) || normalized.contains(existing.normalized)) {
                if normalized.count > existing.normalized.count + 20 {
                    try? store.update(id: existing.id, content: content, category: category)
                    reload()
                } else {
                    try? store.bumpRelevance(id: existing.id)
                    reload()
                }
                return
            }
        }
        _ = try? store.insert(content: content, category: category, sourceConversationID: sourceConversationID)
        reload()
    }

    // MARK: - Retrieval

    /// Keyword-overlap retrieval: scores memories against the user's text.
    func relevantMemories(for text: String, limit: Int = 6) -> [MemoryItem] {
        let terms = Set(MemoryItem.normalize(text).split(separator: " ").map(String.init)
            .filter { $0.count > 2 })
        guard !terms.isEmpty else { return [] }
        return memories
            .map { m -> (MemoryItem, Double) in
                let mTerms = Set(m.normalized.split(separator: " ").map(String.init))
                let overlap = Double(terms.intersection(mTerms).count)
                return (m, overlap * (0.5 + m.relevance))
            }
            .filter { $0.1 > 0.5 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { $0.0 }
    }
}
