import Foundation
import SQLite3

/// SQLite3 Persistence Manager matching APP-SECRET.md schema for VoiceOS 0.1.40.
/// Manages local voice sessions, user insights, custom dictionaries, and synchronization metadata.
public final class VoiceOSDatabaseManager: @unchecked Sendable {
    public static let shared = VoiceOSDatabaseManager()
    
    private var db: OpaquePointer?
    private let lock = NSLock()
    
    private init() {
        openDatabase()
        createTables()
    }
    
    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }
    
    // MARK: - Database Setup
    
    private func getDatabaseURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let voiceOSDir = appSupport.appendingPathComponent("VoiceOS", isDirectory: true)
        try? FileManager.default.createDirectory(at: voiceOSDir, withIntermediateDirectories: true)
        return voiceOSDir.appendingPathComponent("voiceos_local.sqlite")
    }
    
    private func openDatabase() {
        let dbURL = getDatabaseURL()
        if sqlite3_open(dbURL.path, &db) != SQLITE_OK {
            // In-memory fallback if disk access is restricted
            sqlite3_open(":memory:", &db)
        }
    }
    
    private func createTables() {
        lock.lock()
        defer { lock.unlock() }
        
        // Exact schema extracted from APP-SECRET.md line 122-131
        let insightsSQL = """
        CREATE TABLE IF NOT EXISTS voice_session_insights (
          id TEXT PRIMARY KEY,
          user_id TEXT,
          source_updated_at TEXT NOT NULL,
          metrics_json TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_voice_session_insights_user
          ON voice_session_insights(user_id);
        """
        
        // Additional documented tables: voice_sessions, dictionary_items, integrations
        let sessionsSQL = """
        CREATE TABLE IF NOT EXISTS voice_sessions (
          id TEXT PRIMARY KEY,
          user_id TEXT,
          transcript TEXT NOT NULL,
          mode TEXT NOT NULL,
          duration_ms REAL,
          created_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS dictionary_items (
          id TEXT PRIMARY KEY,
          word TEXT NOT NULL UNIQUE,
          replacement TEXT NOT NULL,
          locale TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS integration_records (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          category TEXT NOT NULL,
          status TEXT NOT NULL,
          auth_metadata TEXT
        );
        """
        
        sqlite3_exec(db, insightsSQL, nil, nil, nil)
        sqlite3_exec(db, sessionsSQL, nil, nil, nil)
    }
    
    // MARK: - Insights CRUD
    
    public func insertInsight(id: String, userId: String, sourceUpdatedAt: String, metricsJSON: String) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        let query = "INSERT OR REPLACE INTO voice_session_insights (id, user_id, source_updated_at, metrics_json) VALUES (?, ?, ?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (userId as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (sourceUpdatedAt as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 4, (metricsJSON as NSString).utf8String, -1, nil)
        
        return sqlite3_step(stmt) == SQLITE_DONE
    }
    
    public func fetchInsights(for userId: String) -> [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        
        let query = "SELECT id, user_id, source_updated_at, metrics_json FROM voice_session_insights WHERE user_id = ? ORDER BY source_updated_at DESC;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, (userId as NSString).utf8String, -1, nil)
        
        var results: [[String: Any]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(stmt, 0))
            let uid = String(cString: sqlite3_column_text(stmt, 1))
            let updatedAt = String(cString: sqlite3_column_text(stmt, 2))
            let metrics = String(cString: sqlite3_column_text(stmt, 3))
            results.append([
                "id": id,
                "user_id": uid,
                "source_updated_at": updatedAt,
                "metrics_json": metrics
            ])
        }
        return results
    }
    
    // MARK: - Voice Sessions CRUD
    
    public func insertSession(id: String, userId: String, transcript: String, mode: String, durationMs: Double) {
        lock.lock()
        defer { lock.unlock() }
        
        let query = "INSERT OR REPLACE INTO voice_sessions (id, user_id, transcript, mode, duration_ms, created_at) VALUES (?, ?, ?, ?, ?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        
        let now = ISO8601DateFormatter().string(from: Date())
        sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (userId as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (transcript as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 4, (mode as NSString).utf8String, -1, nil)
        sqlite3_bind_double(stmt, 5, durationMs)
        sqlite3_bind_text(stmt, 6, (now as NSString).utf8String, -1, nil)
        
        sqlite3_step(stmt)
    }
    
    public func fetchRecentSessions(limit: Int = 50) -> [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        
        let query = "SELECT id, user_id, transcript, mode, duration_ms, created_at FROM voice_sessions ORDER BY created_at DESC LIMIT ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_int(stmt, 1, Int32(limit))
        
        var sessions: [[String: Any]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(stmt, 0))
            let uid = String(cString: sqlite3_column_text(stmt, 1))
            let text = String(cString: sqlite3_column_text(stmt, 2))
            let mode = String(cString: sqlite3_column_text(stmt, 3))
            let duration = sqlite3_column_double(stmt, 4)
            let createdAt = String(cString: sqlite3_column_text(stmt, 5))
            
            sessions.append([
                "id": id,
                "user_id": uid,
                "transcript": text,
                "mode": mode,
                "duration_ms": duration,
                "created_at": createdAt
            ])
        }
        return sessions
    }
}

