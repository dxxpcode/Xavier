import Foundation
import SQLite3

/// CRUD for conversations and messages, backed by SQLite.
final class ConversationStore {
    private let db: Database

    init(db: Database) { self.db = db }

    // MARK: Conversations

    func createConversation(title: String = "New conversation") throws -> Conversation {
        let c = Conversation(id: UUID().uuidString, title: title,
                             excludedFromMemory: false, createdAt: Date(), updatedAt: Date())
        try db.run("INSERT INTO conversations (id, title, excluded_from_memory, created_at, updated_at) VALUES (?, ?, 0, ?, ?);") { s in
            Database.bindText(s, 1, c.id)
            Database.bindText(s, 2, c.title)
            sqlite3_bind_double(s, 3, c.createdAt.timeIntervalSince1970)
            sqlite3_bind_double(s, 4, c.updatedAt.timeIntervalSince1970)
        }
        return c
    }

    func listConversations(limit: Int = 200) throws -> [Conversation] {
        try db.query("SELECT id, title, excluded_from_memory, created_at, updated_at FROM conversations ORDER BY updated_at DESC LIMIT ?;") { s in
            sqlite3_bind_int(s, 1, Int32(limit))
        } row: { s in
            Conversation(id: Database.text(s, 0), title: Database.text(s, 1),
                         excludedFromMemory: sqlite3_column_int(s, 2) != 0,
                         createdAt: Date(timeIntervalSince1970: sqlite3_column_double(s, 3)),
                         updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(s, 4)))
        }
    }

    func conversation(id: String) throws -> Conversation? {
        try db.query("SELECT id, title, excluded_from_memory, created_at, updated_at FROM conversations WHERE id = ?;") { s in
            Database.bindText(s, 1, id)
        } row: { s in
            Conversation(id: Database.text(s, 0), title: Database.text(s, 1),
                         excludedFromMemory: sqlite3_column_int(s, 2) != 0,
                         createdAt: Date(timeIntervalSince1970: sqlite3_column_double(s, 3)),
                         updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(s, 4)))
        }.first
    }

    func renameConversation(id: String, title: String) throws {
        try db.run("UPDATE conversations SET title = ?, updated_at = ? WHERE id = ?;") { s in
            Database.bindText(s, 1, title)
            sqlite3_bind_double(s, 2, Date().timeIntervalSince1970)
            Database.bindText(s, 3, id)
        }
    }

    func isExcludedFromMemory(id: String) throws -> Bool {
        try db.query("SELECT excluded_from_memory FROM conversations WHERE id = ?;") { s in
            Database.bindText(s, 1, id)
        } row: { s in
            sqlite3_column_int(s, 0) != 0
        }.first ?? false
    }

    func setExcludedFromMemory(id: String, excluded: Bool) throws {
        try db.run("UPDATE conversations SET excluded_from_memory = ? WHERE id = ?;") { s in
            sqlite3_bind_int(s, 1, excluded ? 1 : 0)
            Database.bindText(s, 2, id)
        }
    }

    func deleteConversation(id: String) throws {
        try db.run("DELETE FROM conversations WHERE id = ?;") { s in
            Database.bindText(s, 1, id)
        }
        // Memories are intentionally retained; they are independent of conversation storage.
    }

    func searchConversations(_ query: String) throws -> [Conversation] {
        let like = "%\(query)%"
        return try db.query("""
            SELECT DISTINCT c.id, c.title, c.excluded_from_memory, c.created_at, c.updated_at
            FROM conversations c LEFT JOIN messages m ON m.conversation_id = c.id
            WHERE c.title LIKE ? OR m.content LIKE ?
            ORDER BY c.updated_at DESC LIMIT 50;
        """) { s in
            Database.bindText(s, 1, like)
            Database.bindText(s, 2, like)
        } row: { s in
            Conversation(id: Database.text(s, 0), title: Database.text(s, 1),
                         excludedFromMemory: sqlite3_column_int(s, 2) != 0,
                         createdAt: Date(timeIntervalSince1970: sqlite3_column_double(s, 3)),
                         updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(s, 4)))
        }
    }

    // MARK: Messages

    func appendMessage(conversationID: String, role: MessageRole, content: String, isComplete: Bool = true) throws -> ChatMessage {
        let m = ChatMessage(id: UUID().uuidString, conversationID: conversationID,
                            role: role, content: content, isComplete: isComplete, createdAt: Date())
        try db.run("INSERT INTO messages (id, conversation_id, role, content, is_complete, created_at) VALUES (?, ?, ?, ?, ?, ?);") { s in
            Database.bindText(s, 1, m.id)
            Database.bindText(s, 2, m.conversationID)
            Database.bindText(s, 3, m.role.rawValue)
            Database.bindText(s, 4, m.content)
            sqlite3_bind_int(s, 5, m.isComplete ? 1 : 0)
            sqlite3_bind_double(s, 6, m.createdAt.timeIntervalSince1970)
        }
        try touchConversation(id: conversationID)
        return m
    }

    func updateMessage(id: String, content: String, isComplete: Bool) throws {
        try db.run("UPDATE messages SET content = ?, is_complete = ? WHERE id = ?;") { s in
            Database.bindText(s, 1, content)
            sqlite3_bind_int(s, 2, isComplete ? 1 : 0)
            Database.bindText(s, 3, id)
        }
    }

    func deleteMessage(id: String) throws {
        try db.run("DELETE FROM messages WHERE id = ?;") { s in
            Database.bindText(s, 1, id)
        }
    }

    func messages(forConversation id: String, limit: Int = 500) throws -> [ChatMessage] {
        try db.query("SELECT id, conversation_id, role, content, is_complete, created_at FROM messages WHERE conversation_id = ? ORDER BY created_at ASC LIMIT ?;") { s in
            Database.bindText(s, 1, id)
            sqlite3_bind_int(s, 2, Int32(limit))
        } row: { s in
            ChatMessage(id: Database.text(s, 0), conversationID: Database.text(s, 1),
                        role: MessageRole(rawValue: Database.text(s, 2)) ?? .user,
                        content: Database.text(s, 3),
                        isComplete: sqlite3_column_int(s, 4) != 0,
                        createdAt: Date(timeIntervalSince1970: sqlite3_column_double(s, 5)))
        }
    }

    func latestConversation() throws -> Conversation? {
        try listConversations(limit: 1).first
    }

    private func touchConversation(id: String) throws {
        try db.run("UPDATE conversations SET updated_at = ? WHERE id = ?;") { s in
            sqlite3_bind_double(s, 1, Date().timeIntervalSince1970)
            Database.bindText(s, 2, id)
        }
    }

    /// Marks the conversation's title from its first exchange.
    func autoTitle(id: String, from text: String) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = String(trimmed.prefix(48))
        try renameConversation(id: id, title: title.isEmpty ? "Conversation" : title)
    }
}
