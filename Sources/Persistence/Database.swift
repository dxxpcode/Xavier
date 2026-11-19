import Foundation
import SQLite3

/// Thin synchronous SQLite wrapper. All calls are serialized on a private queue.
final class Database {
    enum DBError: Error {
        case openFailed(String)
        case prepareFailed(String)
        case stepFailed(String)
    }

    nonisolated(unsafe) private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.dxxpcode.xavier.db")

    init() throws {
        let dir = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("Xavier", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("xavier.db").path
        if sqlite3_open(path, &db) != SQLITE_OK {
            throw DBError.openFailed(String(cString: sqlite3_errmsg(db)))
        }
        try exec("PRAGMA journal_mode = WAL;")
        try exec("PRAGMA foreign_keys = ON;")
        try migrate()
    }

    deinit { sqlite3_close(db) }

    private func migrate() throws {
        try exec("""
        CREATE TABLE IF NOT EXISTS conversations (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            excluded_from_memory INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        """)
        try exec("""
        CREATE TABLE IF NOT EXISTS messages (
            id TEXT PRIMARY KEY,
            conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
            role TEXT NOT NULL,
            content TEXT NOT NULL,
            is_complete INTEGER NOT NULL DEFAULT 1,
            created_at REAL NOT NULL
        );
        """)
        try exec("CREATE INDEX IF NOT EXISTS idx_messages_conversation ON messages(conversation_id, created_at);")
        try exec("""
        CREATE TABLE IF NOT EXISTS memories (
            id TEXT PRIMARY KEY,
            content TEXT NOT NULL,
            category TEXT NOT NULL,
            normalized TEXT NOT NULL,
            relevance REAL NOT NULL DEFAULT 0.5,
            source_conversation_id TEXT,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        """)
        try exec("CREATE INDEX IF NOT EXISTS idx_memories_normalized ON memories(normalized);")
    }

    func exec(_ sql: String) throws {
        try queue.sync {
            var err: UnsafeMutablePointer<CChar>?
            if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
                let msg = err.map { String(cString: $0) } ?? "unknown"
                sqlite3_free(err)
                throw DBError.stepFailed(msg)
            }
        }
    }

    /// Runs a statement with bound parameters. `bind` gets the statement; `row` maps each result row.
    func query<T>(_ sql: String, bind: (OpaquePointer) -> Void = { _ in }, row: (OpaquePointer) -> T) throws -> [T] {
        try queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(stmt) }
            bind(stmt!)
            var results: [T] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                results.append(row(stmt!))
            }
            return results
        }
    }

    func run(_ sql: String, bind: (OpaquePointer) -> Void = { _ in }) throws {
        _ = try query(sql, bind: bind) { _ in () }
    }

    // MARK: - Bind helpers

    static func bindText(_ stmt: OpaquePointer, _ index: Int32, _ value: String) {
        sqlite3_bind_text(stmt, index, (value as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }

    static func text(_ stmt: OpaquePointer, _ index: Int32) -> String {
        guard let c = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: c)
    }
}
