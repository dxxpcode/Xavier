import Foundation
import OSLog

enum XavierLog {
    static let subsystem = "com.dxxpcode.xavier"
    static let general = Logger(subsystem: subsystem, category: "general")
    static let inference = Logger(subsystem: subsystem, category: "inference")
    static let voice = Logger(subsystem: subsystem, category: "voice")
    static let memory = Logger(subsystem: subsystem, category: "memory")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")

    /// Local log file for the Advanced preferences pane.
    static let logFileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("Xavier", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("xavier.log")
    }()

    static func appLog(_ line: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let entry = "[\(stamp)] \(line)\n"
        if let data = entry.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: logFileURL) {
                handle.seekToEndOfFile(); handle.write(data); try? handle.close()
            } else {
                try? data.write(to: logFileURL)
            }
        }
    }
}
