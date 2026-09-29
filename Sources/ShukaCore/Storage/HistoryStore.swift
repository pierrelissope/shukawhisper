import Foundation
import SQLite3

/// Local SQLite-backed history of dictations and transforms.
public actor HistoryStore {
    /// Owns the SQLite connection and closes it when the store goes away.
    private final class Connection: @unchecked Sendable {
        let handle: OpaquePointer?
        init(_ handle: OpaquePointer?) { self.handle = handle }
        deinit { sqlite3_close(handle) }
    }

    private let connection: Connection
    private var db: OpaquePointer? { connection.handle }

    /// - Parameter url: Database file; `nil` opens an in-memory database (tests).
    public init(url: URL?) throws {
        if let url {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        var handle: OpaquePointer?
        guard sqlite3_open(url?.path ?? ":memory:", &handle) == SQLITE_OK else {
            defer { sqlite3_close(handle) }
            throw HistoryError.sqlite(String(cString: sqlite3_errmsg(handle)))
        }
        connection = Connection(handle)
        try Self.exec(handle, """
            PRAGMA journal_mode = WAL;
            CREATE TABLE IF NOT EXISTS entries (
                id TEXT PRIMARY KEY,
                date REAL NOT NULL,
                kind TEXT NOT NULL,
                raw_text TEXT NOT NULL,
                final_text TEXT NOT NULL,
                app_name TEXT,
                bundle_id TEXT,
                label TEXT,
                audio_duration REAL NOT NULL DEFAULT 0,
                latency REAL NOT NULL DEFAULT 0,
                word_count INTEGER NOT NULL DEFAULT 0,
                error TEXT
            );
            CREATE INDEX IF NOT EXISTS entries_date ON entries(date DESC);
            """)
    }

    public func insert(_ entry: HistoryEntry) throws {
        let sql = """
            INSERT OR REPLACE INTO entries
            (id, date, kind, raw_text, final_text, app_name, bundle_id, label, audio_duration, latency, word_count, error)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        try withStatement(sql) { statement in
            bind(statement, 1, entry.id.uuidString)
            sqlite3_bind_double(statement, 2, entry.date.timeIntervalSince1970)
            bind(statement, 3, entry.kind.rawValue)
            bind(statement, 4, entry.rawText)
            bind(statement, 5, entry.finalText)
            bind(statement, 6, entry.appName)
            bind(statement, 7, entry.bundleID)
            bind(statement, 8, entry.label)
            sqlite3_bind_double(statement, 9, entry.audioDuration)
            sqlite3_bind_double(statement, 10, entry.latency)
            sqlite3_bind_int64(statement, 11, Int64(entry.wordCount))
            bind(statement, 12, entry.errorMessage)
            try step(statement)
        }
    }

    /// Most recent entries first, optionally filtered by a case-insensitive text search.
    public func recent(limit: Int = 200, matching search: String = "") throws -> [HistoryEntry] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let sql = query.isEmpty
            ? "SELECT * FROM entries ORDER BY date DESC LIMIT ?"
            : "SELECT * FROM entries WHERE final_text LIKE ? OR raw_text LIKE ? ORDER BY date DESC LIMIT ?"
        return try withStatement(sql) { statement in
            var index: Int32 = 1
            if !query.isEmpty {
                let pattern = "%\(query)%"
                bind(statement, 1, pattern)
                bind(statement, 2, pattern)
                index = 3
            }
            sqlite3_bind_int64(statement, index, Int64(limit))
            var entries: [HistoryEntry] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                entries.append(Self.entry(from: statement))
            }
            return entries
        }
    }

    /// Lightweight rows for computing usage statistics over the whole history.
    public func statsSamples() throws -> [UsageStats.Sample] {
        try withStatement("SELECT date, word_count, audio_duration FROM entries WHERE error IS NULL AND kind != 'transform'") { statement in
            var samples: [UsageStats.Sample] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                samples.append(.init(
                    date: Date(timeIntervalSince1970: sqlite3_column_double(statement, 0)),
                    words: Int(sqlite3_column_int64(statement, 1)),
                    duration: sqlite3_column_double(statement, 2)
                ))
            }
            return samples
        }
    }

    public func delete(id: UUID) throws {
        try withStatement("DELETE FROM entries WHERE id = ?") { statement in
            bind(statement, 1, id.uuidString)
            try step(statement)
        }
    }

    public func deleteAll() throws {
        try Self.exec(db, "DELETE FROM entries")
    }

    // MARK: - SQLite plumbing

    private static func entry(from statement: OpaquePointer) -> HistoryEntry {
        func text(_ column: Int32) -> String? {
            sqlite3_column_text(statement, column).map { String(cString: $0) }
        }
        return HistoryEntry(
            id: UUID(uuidString: text(0) ?? "") ?? UUID(),
            date: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
            kind: HistoryEntry.Kind(rawValue: text(2) ?? "") ?? .dictation,
            rawText: text(3) ?? "",
            finalText: text(4) ?? "",
            appName: text(5),
            bundleID: text(6),
            label: text(7),
            audioDuration: sqlite3_column_double(statement, 8),
            latency: sqlite3_column_double(statement, 9),
            errorMessage: text(11)
        )
    }

    private func withStatement<T>(_ sql: String, _ body: (OpaquePointer) throws -> T) throws -> T {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw HistoryError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        return try body(statement)
    }

    private func step(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw HistoryError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func bind(_ statement: OpaquePointer, _ index: Int32, _ value: String?) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_text(statement, index, value, -1, Self.transient)
    }

    private static func exec(_ db: OpaquePointer?, _ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw HistoryError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
    }

    /// Tells SQLite to copy bound strings (`SQLITE_TRANSIENT`).
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}

public enum HistoryError: Error, LocalizedError {
    case sqlite(String)
    public var errorDescription: String? {
        if case let .sqlite(message) = self { return "History database error: \(message)" }
        return nil
    }
}
