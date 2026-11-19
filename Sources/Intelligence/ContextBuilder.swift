import Foundation

/// Builds inference requests from conversation history and relevant memories,
/// staying inside a practical context budget (~4 chars/token heuristic).
struct ContextBuilder {
    /// Approximate character budget for conversation history (≈6k tokens).
    var historyCharacterBudget = 24_000
    var memoryCharacterBudget = 2_000

    func systemPrompt(memories: [MemoryItem], memoryEnabled: Bool) -> String {
        var prompt = """
        You are Xavier, a personal AI assistant on macOS. You are helpful, concise, and \
        direct. You run entirely on the user's machine. Format responses in Markdown \
        when it improves readability. Today is \(Date().formatted(date: .long, time: .omitted)).
        """
        if memoryEnabled && !memories.isEmpty {
            var block = "\n\nThings you remember about the user:"
            var used = 0
            for memory in memories {
                let line = "\n- \(memory.content)"
                if used + line.count > memoryCharacterBudget { break }
                block += line
                used += line.count
            }
            prompt += block
        }
        return prompt
    }

    /// Returns the turns to send: system prompt plus as much recent history as fits.
    func buildTurns(messages: [ChatMessage], memories: [MemoryItem], memoryEnabled: Bool) -> [ChatTurn] {
        var turns = [ChatTurn(role: .system, content: systemPrompt(memories: memories, memoryEnabled: memoryEnabled))]
        var budget = historyCharacterBudget
        // Walk history backwards; keep the most recent messages that fit.
        var kept: [ChatTurn] = []
        for message in messages.reversed() {
            let cost = message.content.count + 32
            if cost > budget && !kept.isEmpty { break }
            budget -= cost
            kept.append(ChatTurn(role: message.role, content: message.content))
        }
        turns.append(contentsOf: kept.reversed())
        return turns
    }
}
