import Foundation

enum MessageRole: String, Codable {
    case user
    case assistant
    case system
}

struct Conversation: Identifiable, Hashable {
    let id: String
    var title: String
    var excludedFromMemory: Bool
    let createdAt: Date
    var updatedAt: Date
}

struct ChatMessage: Identifiable, Hashable {
    let id: String
    let conversationID: String
    var role: MessageRole
    var content: String
    var isComplete: Bool
    let createdAt: Date
}

enum MemoryCategory: String, CaseIterable, Codable {
    case preference = "Preference"
    case project = "Project"
    case workContext = "Work"
    case fact = "Fact"
    case instruction = "Instruction"
    case goal = "Goal"
    case recurring = "Recurring"
}

struct MemoryItem: Identifiable, Hashable {
    let id: String
    var content: String
    var category: MemoryCategory
    var normalized: String
    var relevance: Double
    var sourceConversationID: String?
    let createdAt: Date
    var updatedAt: Date

    static func normalize(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
