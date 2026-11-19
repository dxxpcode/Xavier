import Foundation
import SQLite3

/// Persistent store for personal memories.
final class MemoryStore {
    private let db: Database

    init(db: Database) { self.db = db }

    func all() throws -> [MemoryItem] {
        try db.query("SELECT id, content, category, normalized, relevance, source_conversation_id, created_at, updated_at FROM memories ORDER BY updated_at DESC;") { _ in } row: { s in
            MemoryItem(id: Database.text(s, 0), content: Database.text(s, 1),
                       category: MemoryCategory(rawValue: Database.text(s, 2)) ?? .fact,
                       normalized: Database.text(s, 3),
                       relevance: sqlite3_column_double(s, 4),
                       sourceConversationID: sqlite3_column_type(s, 5) == SQLITE_NULL ? nil : Database.text(s, 5),
                       createdAt: Date(timeIntervalSince1970: sqlite3_column_double(s, 6)),
                       updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(s, 7)))
        }
    }

    @discardableResult
    func insert(content: String, category: MemoryCategory, sourceConversationID: String?) throws -> MemoryItem {
        let m = MemoryItem(id: UUID().uuidString, content: content, category: category,
                           normalized: MemoryItem.normalize(content), relevance: 0.6,
                           sourceConversationID: sourceConversationID,
                           createdAt: Date(), updatedAt: Date())
        try db.run("INSERT INTO memories (id, content, category, normalized, relevance, source_conversation_id, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?);") { s in
            Database.bindText(s, 1, m.id)
            Database.bindText(s, 2, m.content)
            Database.bindText(s, 3, m.category.rawValue)
            Database.bindText(s, 4, m.normalized)
            sqlite3_bind_double(s, 5, m.relevance)
            if let src = m.sourceConversationID { Database.bindText(s, 6, src) } else { sqlite3_bind_null(s, 6) }
            sqlite3_bind_double(s, 7, m.createdAt.timeIntervalSince1970)
            sqlite3_bind_double(s, 8, m.updatedAt.timeIntervalSince1970)
        }
        return m
    }

    func update(id: String, content: String, category: MemoryCategory) throws {
        try db.run("UPDATE memories SET content = ?, category = ?, normalized = ?, updated_at = ? WHERE id = ?;") { s in
            Database.bindText(s, 1, content)
            Database.bindText(s, 2, category.rawValue)
            Database.bindText(s, 3, MemoryItem.normalize(content))
            sqlite3_bind_double(s, 4, Date().timeIntervalSince1970)
            Database.bindText(s, 5, id)
        }
    }

    func bumpRelevance(id: String) throws {
        try db.run("UPDATE memories SET relevance = MIN(1.0, relevance + 0.1), updated_at = ? WHERE id = ?;") { s in
            sqlite3_bind_double(s, 1, Date().timeIntervalSince1970)
            Database.bindText(s, 2, id)
        }
    }

    func delete(id: String) throws {
        try db.run("DELETE FROM memories WHERE id = ?;") { s in
            Database.bindText(s, 1, id)
        }
    }

    func deleteAll() throws {
        try db.exec("DELETE FROM memories;")
    }

    /// Keyword search for the memory management UI and retrieval.
    func search(_ query: String) throws -> [MemoryItem] {
        let like = "%\(MemoryItem.normalize(query))%"
        return try db.query("SELECT id, content, category, normalized, relevance, source_conversation_id, created_at, updated_at FROM memories WHERE normalized LIKE ? ORDER BY relevance DESC, updated_at DESC;") { s in
            Database.bindText(s, 1, like)
        } row: { s in
            MemoryItem(id: Database.text(s, 0), content: Database.text(s, 1),
                       category: MemoryCategory(rawValue: Database.text(s, 2)) ?? .fact,
                       normalized: Database.text(s, 3),
                       relevance: sqlite3_column_double(s, 4),
                       sourceConversationID: sqlite3_column_type(s, 5) == SQLITE_NULL ? nil : Database.text(s, 5),
                       createdAt: Date(timeIntervalSince1970: sqlite3_column_double(s, 6)),
                       updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(s, 7)))
        }
    }
}
