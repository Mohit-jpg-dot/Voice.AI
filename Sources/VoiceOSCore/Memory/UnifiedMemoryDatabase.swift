import Foundation
import SQLite3
import CommonCrypto
import Security

public final class UnifiedMemoryDatabase: @unchecked Sendable {
    public static let shared = UnifiedMemoryDatabase()
    
    private let lock = NSLock()
    private var db: OpaquePointer?
    private var activeAccountId: String = "local_default"
    private var isInitialized = false
    
    // Privacy & Pause Controls
    public var isPaused: Bool = false
    public var isIncognito: Bool = false
    
    private init() {
        openDatabase(for: "local_default")
    }
    
    deinit {
        closeDatabase()
    }
    
    // MARK: - Lifecycle & AES-256 Storage Paths
    
    private func memoryDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Voice.AI/UnifiedMemory", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    private func encryptedFilePath(for accountId: String) -> URL {
        let hash = sha256Hex(accountId)
        return memoryDirectory().appendingPathComponent("unified_memory_\(hash).sqlite.enc")
    }
    
    private func workingDbPath(for accountId: String) -> URL {
        let hash = sha256Hex(accountId)
        return memoryDirectory().appendingPathComponent(".working_\(hash).sqlite")
    }
    
    private func getOrCreateEncryptionKey(for accountId: String) -> Data {
        let keyName = "ai.voice.app.unified_memory.key.\(accountId)"
        if let existingB64 = KeychainService.shared.get(keyName), let data = Data(base64Encoded: existingB64) {
            return data
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let keyData = Data(bytes)
        KeychainService.shared.set(keyData.base64EncodedString(), for: keyName)
        return keyData
    }
    
    public func openDatabase(for accountId: String) {
        lock.lock()
        defer { lock.unlock() }
        
        if activeAccountId == accountId && db != nil {
            return
        }
        
        if db != nil {
            persistEncryptedDatabaseLocked()
            sqlite3_close(db)
            db = nil
        }
        
        activeAccountId = accountId
        let workingPath = workingDbPath(for: accountId)
        let encPath = encryptedFilePath(for: accountId)
        
        // Decrypt if encrypted storage file exists
        if FileManager.default.fileExists(atPath: encPath.path),
           let encData = try? Data(contentsOf: encPath) {
            let key = getOrCreateEncryptionKey(for: accountId)
            if let decrypted = aesDecrypt(data: encData, key: key) {
                try? decrypted.write(to: workingPath, options: .atomic)
            }
        }
        
        // Set POSIX permissions 0600 on working database
        if sqlite3_open(workingPath.path, &db) != SQLITE_OK {
            // Fallback to in-memory SQLite if sandbox disk restricted
            sqlite3_open(":memory:", &db)
        } else {
            // Secure permissions
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: workingPath.path)
        }
        
        createTablesLocked()
        runMigrationIfNeededLocked()
        isInitialized = true
    }
    
    public func closeDatabase() {
        lock.lock()
        defer { lock.unlock() }
        guard let validDb = db else { return }
        persistEncryptedDatabaseLocked()
        sqlite3_close(validDb)
        db = nil
    }
    
    // MARK: - Schema & Tables Setup (including FTS5)
    
    private func createTablesLocked() {
        guard let db = db else { return }
        
        let schemaSQL = """
        PRAGMA journal_mode = WAL;
        PRAGMA synchronous = NORMAL;
        
        CREATE TABLE IF NOT EXISTS conversations (
            id TEXT PRIMARY KEY,
            account_id TEXT NOT NULL,
            title TEXT NOT NULL,
            persona TEXT NOT NULL,
            is_pinned INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            rolling_summary TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_conversations_account ON conversations(account_id);
        
        CREATE TABLE IF NOT EXISTS messages (
            id TEXT PRIMARY KEY,
            conversation_id TEXT NOT NULL,
            role TEXT NOT NULL,
            raw_content TEXT NOT NULL,
            corrected_content TEXT,
            original_language TEXT,
            timestamp REAL NOT NULL,
            actions_json TEXT,
            cited_sources_json TEXT,
            token_count INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS idx_messages_conv ON messages(conversation_id);
        
        CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
            id UNINDEXED,
            conversation_id UNINDEXED,
            content
        );
        
        CREATE TABLE IF NOT EXISTS summaries (
            id TEXT PRIMARY KEY,
            conversation_id TEXT NOT NULL,
            turn_start_id TEXT,
            turn_end_id TEXT,
            summary TEXT NOT NULL,
            key_decisions_json TEXT,
            open_questions_json TEXT,
            entities_json TEXT,
            created_at REAL NOT NULL
        );
        
        CREATE VIRTUAL TABLE IF NOT EXISTS summaries_fts USING fts5(
            id UNINDEXED,
            conversation_id UNINDEXED,
            summary
        );
        
        CREATE TABLE IF NOT EXISTS facts (
            id TEXT PRIMARY KEY,
            account_id TEXT NOT NULL,
            category TEXT NOT NULL,
            fact_key TEXT,
            content TEXT NOT NULL,
            provenance_session_id TEXT,
            provenance_type TEXT NOT NULL,
            confidence REAL NOT NULL DEFAULT 1.0,
            is_superseded INTEGER NOT NULL DEFAULT 0,
            superseded_by_id TEXT,
            tags_json TEXT,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_facts_account ON facts(account_id);
        CREATE INDEX IF NOT EXISTS idx_facts_key ON facts(fact_key);
        
        CREATE VIRTUAL TABLE IF NOT EXISTS facts_fts USING fts5(
            id UNINDEXED,
            account_id UNINDEXED,
            content,
            tags
        );
        
        CREATE TABLE IF NOT EXISTS corrections (
            id TEXT PRIMARY KEY,
            account_id TEXT NOT NULL,
            target_type TEXT NOT NULL,
            target_id TEXT NOT NULL,
            original_value TEXT NOT NULL,
            corrected_value TEXT NOT NULL,
            reason TEXT,
            timestamp REAL NOT NULL
        );
        
        CREATE TABLE IF NOT EXISTS tasks (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            request_text TEXT NOT NULL,
            plan TEXT NOT NULL,
            status TEXT NOT NULL,
            evidence TEXT,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            expires_at REAL
        );
        CREATE INDEX IF NOT EXISTS idx_tasks_session ON tasks(session_id);
        
        CREATE TABLE IF NOT EXISTS entities (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            name TEXT NOT NULL,
            kind TEXT NOT NULL,
            salience REAL NOT NULL DEFAULT 1.0,
            metadata_json TEXT,
            last_mentioned_at REAL NOT NULL
        );
        
        CREATE TABLE IF NOT EXISTS embeddings (
            id TEXT PRIMARY KEY,
            target_type TEXT NOT NULL,
            target_id TEXT NOT NULL,
            provider TEXT NOT NULL,
            dimensions INTEGER NOT NULL,
            vector_blob BLOB NOT NULL,
            created_at REAL NOT NULL
        );
        """
        
        sqlite3_exec(db, schemaSQL, nil, nil, nil)
    }
    
    // MARK: - Save and Encryption at Rest
    
    public func persistEncryptedDatabase() {
        lock.lock()
        defer { lock.unlock() }
        persistEncryptedDatabaseLocked()
    }
    
    private func persistEncryptedDatabaseLocked() {
        guard !isIncognito else { return } // Incognito never persists to disk
        guard let db = db else { return }
        
        // Flush WAL to disk
        sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, nil)
        
        let workingPath = workingDbPath(for: activeAccountId)
        guard let rawDbData = try? Data(contentsOf: workingPath) else { return }
        
        let key = getOrCreateEncryptionKey(for: activeAccountId)
        guard let encrypted = aesEncrypt(data: rawDbData, key: key) else { return }
        
        let encPath = encryptedFilePath(for: activeAccountId)
        try? encrypted.write(to: encPath, options: .atomic)
    }
    
    // MARK: - Conversation & Message Operations
    
    public func saveConversation(_ conv: ConversationSessionRecord) {
        lock.lock()
        defer { lock.unlock() }
        guard !isPaused, let db = db else { return }
        
        let query = """
        INSERT OR REPLACE INTO conversations (id, account_id, title, persona, is_pinned, created_at, updated_at, rolling_summary)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (conv.id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (conv.accountId as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 3, (conv.title as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 4, (conv.persona as NSString).utf8String, -1, nil)
            sqlite3_bind_int(stmt, 5, conv.isPinned ? 1 : 0)
            sqlite3_bind_double(stmt, 6, conv.createdAt.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 7, conv.updatedAt.timeIntervalSince1970)
            if let rs = conv.rollingSummary {
                sqlite3_bind_text(stmt, 8, (rs as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 8)
            }
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        
        for msg in conv.messages {
            insertMessageLocked(msg, conversationId: conv.id)
        }
        persistEncryptedDatabaseLocked()
    }
    
    public func insertMessage(_ msg: MessageRecordItem, conversationId: String) {
        lock.lock()
        defer { lock.unlock() }
        guard !isPaused else { return }
        insertMessageLocked(msg, conversationId: conversationId)
        persistEncryptedDatabaseLocked()
    }
    
    private func insertMessageLocked(_ msg: MessageRecordItem, conversationId: String) {
        guard let db = db else { return }
        let query = """
        INSERT OR REPLACE INTO messages (id, conversation_id, role, raw_content, corrected_content, original_language, timestamp, actions_json, cited_sources_json, token_count)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            let actionsData = (try? JSONEncoder().encode(msg.actions)) ?? Data()
            let actionsJSON = String(data: actionsData, encoding: .utf8) ?? "[]"
            let sourcesData = (try? JSONEncoder().encode(msg.citedSources)) ?? Data()
            let sourcesJSON = String(data: sourcesData, encoding: .utf8) ?? "[]"
            let tokens = WorkingContextManager.estimateTokens(for: msg.content)
            
            sqlite3_bind_text(stmt, 1, (msg.id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (conversationId as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 3, (msg.role as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 4, (msg.content as NSString).utf8String, -1, nil)
            sqlite3_bind_null(stmt, 5) // corrected_content optional
            sqlite3_bind_text(stmt, 6, (msg.originalLanguage as NSString).utf8String, -1, nil)
            sqlite3_bind_double(stmt, 7, msg.timestamp.timeIntervalSince1970)
            sqlite3_bind_text(stmt, 8, (actionsJSON as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 9, (sourcesJSON as NSString).utf8String, -1, nil)
            sqlite3_bind_int(stmt, 10, Int32(tokens))
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        
        // Index into messages_fts
        let ftsQuery = "INSERT INTO messages_fts (id, conversation_id, content) VALUES (?, ?, ?);"
        var ftsStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, ftsQuery, -1, &ftsStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(ftsStmt, 1, (msg.id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(ftsStmt, 2, (conversationId as NSString).utf8String, -1, nil)
            sqlite3_bind_text(ftsStmt, 3, (msg.content as NSString).utf8String, -1, nil)
            sqlite3_step(ftsStmt)
        }
        sqlite3_finalize(ftsStmt)
    }
    
    // MARK: - Facts & Superseding Operations
    
    public func saveFact(
        id: String = UUID().uuidString,
        category: String,
        key: String? = nil,
        content: String,
        sessionId: String? = nil,
        provenanceType: String = "user_explicit",
        tags: [String] = []
    ) -> String {
        lock.lock()
        defer { lock.unlock() }
        guard !isPaused, let db = db else { return id }
        
        // Check if there is an existing fact with the exact same key to supersede it
        if let k = key, !k.isEmpty {
            let supersedeSQL = """
            UPDATE facts SET is_superseded = 1, superseded_by_id = ?
            WHERE account_id = ? AND fact_key = ? AND is_superseded = 0;
            """
            var supStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, supersedeSQL, -1, &supStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(supStmt, 1, (id as NSString).utf8String, -1, nil)
                sqlite3_bind_text(supStmt, 2, (activeAccountId as NSString).utf8String, -1, nil)
                sqlite3_bind_text(supStmt, 3, (k as NSString).utf8String, -1, nil)
                sqlite3_step(supStmt)
            }
            sqlite3_finalize(supStmt)
        }
        
        let tagsData = (try? JSONEncoder().encode(tags)) ?? Data()
        let tagsJSON = String(data: tagsData, encoding: .utf8) ?? "[]"
        let tagsJoined = tags.joined(separator: " ")
        let now = Date().timeIntervalSince1970
        
        let insertSQL = """
        INSERT OR REPLACE INTO facts (id, account_id, category, fact_key, content, provenance_session_id, provenance_type, confidence, is_superseded, superseded_by_id, tags_json, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, NULL, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (activeAccountId as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 3, (category as NSString).utf8String, -1, nil)
            if let k = key {
                sqlite3_bind_text(stmt, 4, (k as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 4)
            }
            sqlite3_bind_text(stmt, 5, (content as NSString).utf8String, -1, nil)
            if let sid = sessionId {
                sqlite3_bind_text(stmt, 6, (sid as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 6)
            }
            sqlite3_bind_text(stmt, 7, (provenanceType as NSString).utf8String, -1, nil)
            sqlite3_bind_double(stmt, 8, 1.0)
            sqlite3_bind_text(stmt, 9, (tagsJSON as NSString).utf8String, -1, nil)
            sqlite3_bind_double(stmt, 10, now)
            sqlite3_bind_double(stmt, 11, now)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        
        // Index into facts_fts
        let ftsSQL = "INSERT INTO facts_fts (id, account_id, content, tags) VALUES (?, ?, ?, ?);"
        var ftsStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, ftsSQL, -1, &ftsStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(ftsStmt, 1, (id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(ftsStmt, 2, (activeAccountId as NSString).utf8String, -1, nil)
            sqlite3_bind_text(ftsStmt, 3, (content as NSString).utf8String, -1, nil)
            sqlite3_bind_text(ftsStmt, 4, (tagsJoined as NSString).utf8String, -1, nil)
            sqlite3_step(ftsStmt)
        }
        sqlite3_finalize(ftsStmt)
        
        persistEncryptedDatabaseLocked()
        return id
    }
    
    // MARK: - Keyword Search (FTS5)
    
    public func searchFacts(keyword: String, limit: Int = 10) -> [StructuredMemoryItem] {
        lock.lock()
        defer { lock.unlock() }
        guard let db = db else { return [] }
        
        let sanitized = sanitizeFTS5Query(keyword)
        guard !sanitized.isEmpty else { return [] }
        
        let query = """
        SELECT f.id, f.account_id, f.category, f.content, f.tags_json, f.created_at, f.updated_at
        FROM facts_fts fts
        JOIN facts f ON fts.id = f.id
        WHERE facts_fts MATCH ? AND f.account_id = ? AND f.is_superseded = 0
        ORDER BY rank
        LIMIT ?;
        """
        var results: [StructuredMemoryItem] = []
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (sanitized as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (activeAccountId as NSString).utf8String, -1, nil)
            sqlite3_bind_int(stmt, 3, Int32(limit))
            
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(stmt, 0))
                let acc = String(cString: sqlite3_column_text(stmt, 1))
                let cat = String(cString: sqlite3_column_text(stmt, 2))
                let content = String(cString: sqlite3_column_text(stmt, 3))
                let tagsStr = sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? "[]"
                let created = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5))
                let updated = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 6))
                
                let tags = (try? JSONDecoder().decode([String].self, from: tagsStr.data(using: .utf8) ?? Data())) ?? []
                let kind = MemoryFactKind(rawValue: cat) ?? .fact
                let item = StructuredMemoryItem(
                    id: id,
                    accountId: acc,
                    scope: .longTerm,
                    kind: kind,
                    content: content,
                    tags: tags,
                    createdAt: created,
                    updatedAt: updated
                )
                results.append(item)
            }
        }
        sqlite3_finalize(stmt)
        return results
    }
    
    public func searchMessages(keyword: String, conversationId: String? = nil, limit: Int = 10) -> [MessageRecordItem] {
        lock.lock()
        defer { lock.unlock() }
        guard let db = db else { return [] }
        
        let sanitized = sanitizeFTS5Query(keyword)
        guard !sanitized.isEmpty else { return [] }
        
        var query = """
        SELECT m.id, m.role, m.raw_content, m.original_language, m.timestamp, m.actions_json, m.cited_sources_json
        FROM messages_fts fts
        JOIN messages m ON fts.id = m.id
        WHERE messages_fts MATCH ?
        """
        if conversationId != nil {
            query += " AND m.conversation_id = ?"
        }
        query += " ORDER BY rank LIMIT ?;"
        
        var results: [MessageRecordItem] = []
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (sanitized as NSString).utf8String, -1, nil)
            var bindIdx: Int32 = 2
            if let cid = conversationId {
                sqlite3_bind_text(stmt, bindIdx, (cid as NSString).utf8String, -1, nil)
                bindIdx += 1
            }
            sqlite3_bind_int(stmt, bindIdx, Int32(limit))
            
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(stmt, 0))
                let role = String(cString: sqlite3_column_text(stmt, 1))
                let content = String(cString: sqlite3_column_text(stmt, 2))
                let lang = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? "en"
                let ts = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))
                let actionsStr = sqlite3_column_text(stmt, 5).map { String(cString: $0) } ?? "[]"
                let sourcesStr = sqlite3_column_text(stmt, 6).map { String(cString: $0) } ?? "[]"
                
                let actions = (try? JSONDecoder().decode([ActionRecordItem].self, from: actionsStr.data(using: .utf8) ?? Data())) ?? []
                let sources = (try? JSONDecoder().decode([String].self, from: sourcesStr.data(using: .utf8) ?? Data())) ?? []
                
                let msg = MessageRecordItem(
                    id: id,
                    role: role,
                    content: content,
                    originalLanguage: lang,
                    timestamp: ts,
                    actions: actions,
                    citedSources: sources
                )
                results.append(msg)
            }
        }
        sqlite3_finalize(stmt)
        return results
    }
    
    // MARK: - Memory Controls (View, Forget, Clear)
    
    public func allActiveFacts() -> [StructuredMemoryItem] {
        lock.lock()
        defer { lock.unlock() }
        guard let db = db else { return [] }
        
        let query = """
        SELECT id, account_id, category, content, tags_json, created_at, updated_at
        FROM facts
        WHERE account_id = ? AND is_superseded = 0
        ORDER BY updated_at DESC;
        """
        var results: [StructuredMemoryItem] = []
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (activeAccountId as NSString).utf8String, -1, nil)
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(stmt, 0))
                let acc = String(cString: sqlite3_column_text(stmt, 1))
                let cat = String(cString: sqlite3_column_text(stmt, 2))
                let content = String(cString: sqlite3_column_text(stmt, 3))
                let tagsStr = sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? "[]"
                let created = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5))
                let updated = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 6))
                
                let tags = (try? JSONDecoder().decode([String].self, from: tagsStr.data(using: .utf8) ?? Data())) ?? []
                let kind = MemoryFactKind(rawValue: cat) ?? .fact
                let item = StructuredMemoryItem(
                    id: id,
                    accountId: acc,
                    scope: .longTerm,
                    kind: kind,
                    content: content,
                    tags: tags,
                    createdAt: created,
                    updatedAt: updated
                )
                results.append(item)
            }
        }
        sqlite3_finalize(stmt)
        return results
    }
    
    @discardableResult
    public func forgetFact(id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let db = db else { return false }
        
        let query = "DELETE FROM facts WHERE id = ? AND account_id = ?;"
        var stmt: OpaquePointer?
        var success = false
        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (activeAccountId as NSString).utf8String, -1, nil)
            success = sqlite3_step(stmt) == SQLITE_DONE
        }
        sqlite3_finalize(stmt)
        
        // Remove from FTS
        let ftsQuery = "DELETE FROM facts_fts WHERE id = ?;"
        var ftsStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, ftsQuery, -1, &ftsStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(ftsStmt, 1, (id as NSString).utf8String, -1, nil)
            sqlite3_step(ftsStmt)
        }
        sqlite3_finalize(ftsStmt)
        
        persistEncryptedDatabaseLocked()
        return success
    }
    
    @discardableResult
    public func forgetFacts(matching queryText: String) -> Int {
        let matches = searchFacts(keyword: queryText, limit: 50)
        var count = 0
        for m in matches {
            if forgetFact(id: m.id) {
                count += 1
            }
        }
        return count
    }
    
    public func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        guard let db = db else { return }
        let clearSQL = """
        DELETE FROM conversations;
        DELETE FROM messages;
        DELETE FROM messages_fts;
        DELETE FROM summaries;
        DELETE FROM summaries_fts;
        DELETE FROM facts;
        DELETE FROM facts_fts;
        DELETE FROM corrections;
        DELETE FROM tasks;
        DELETE FROM entities;
        DELETE FROM embeddings;
        """
        sqlite3_exec(db, clearSQL, nil, nil, nil)
        persistEncryptedDatabaseLocked()
    }
    
    // MARK: - Migration from Legacy Stores
    
    private func runMigrationIfNeededLocked() {
        let migrationKey = "voiceos.unified_memory.migration_v1.\(activeAccountId)"
        if UserDefaults.standard.bool(forKey: migrationKey) {
            return
        }
        
        print("[UnifiedMemoryDatabase] Migrating legacy stores into unified encrypted database...")
        
        // 1. Ingest legacy ChatMessage from chat_history.json
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let chatFile = appSupport.appendingPathComponent("Voice.AI/chat_history.json")
        if FileManager.default.fileExists(atPath: chatFile.path),
           let data = try? Data(contentsOf: chatFile),
           let messages = try? JSONDecoder().decode([ChatMessage].self, from: data) {
            let legacySessionId = "legacy_chat_session"
            for msg in messages {
                let rec = MessageRecordItem(
                    id: msg.id,
                    role: msg.role,
                    content: msg.text,
                    timestamp: msg.timestamp
                )
                insertMessageLocked(rec, conversationId: legacySessionId)
            }
        }
        
        // 2. Ingest legacy MemoryEntry from memory.json
        let memoryJsonFile = appSupport.appendingPathComponent("Voice.AI/memory.json")
        if FileManager.default.fileExists(atPath: memoryJsonFile.path),
           let data = try? Data(contentsOf: memoryJsonFile),
           let entries = try? JSONDecoder().decode([MemoryEntry].self, from: data) {
            for entry in entries {
                _ = saveFact(
                    id: entry.id,
                    category: entry.category,
                    content: entry.content,
                    provenanceType: "migrated_local_memory",
                    tags: entry.tags
                )
            }
        }
        
        UserDefaults.standard.set(true, forKey: migrationKey)
        persistEncryptedDatabaseLocked()
    }
    
    // MARK: - Utilities & Cryptography
    
    private func sanitizeFTS5Query(_ query: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " *"))
        let filtered = query.unicodeScalars.filter { allowed.contains($0) }
        let clean = String(filtered).trimmingCharacters(in: .whitespacesAndNewlines)
        let terms = clean.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard !terms.isEmpty else { return "" }
        return terms.map { "\"\($0)\"" }.joined(separator: " OR ")
    }
    
    private func sha256Hex(_ string: String) -> String {
        guard let data = string.data(using: .utf8) else { return "0000" }
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    private func aesEncrypt(data: Data, key: Data) -> Data? {
        var iv = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, iv.count, &iv)
        let ivData = Data(iv)
        
        var outBuffer = [UInt8](repeating: 0, count: data.count + kCCBlockSizeAES128)
        var numBytesEncrypted: size_t = 0
        
        let status = CCCrypt(
            CCOperation(kCCEncrypt),
            CCAlgorithm(kCCAlgorithmAES128),
            CCOptions(kCCOptionPKCS7Padding),
            (key as NSData).bytes,
            kCCKeySizeAES256,
            (ivData as NSData).bytes,
            (data as NSData).bytes,
            data.count,
            &outBuffer,
            outBuffer.count,
            &numBytesEncrypted
        )
        guard status == kCCSuccess else { return nil }
        var result = ivData
        result.append(Data(bytes: outBuffer, count: numBytesEncrypted))
        return result
    }
    
    private func aesDecrypt(data: Data, key: Data) -> Data? {
        guard data.count > 16 else { return nil }
        let ivData = data.prefix(16)
        let cipherData = data.dropFirst(16)
        
        var outBuffer = [UInt8](repeating: 0, count: cipherData.count + kCCBlockSizeAES128)
        var numBytesDecrypted: size_t = 0
        
        let status = CCCrypt(
            CCOperation(kCCDecrypt),
            CCAlgorithm(kCCAlgorithmAES128),
            CCOptions(kCCOptionPKCS7Padding),
            (key as NSData).bytes,
            kCCKeySizeAES256,
            (ivData as NSData).bytes,
            (cipherData as NSData).bytes,
            cipherData.count,
            &outBuffer,
            outBuffer.count,
            &numBytesDecrypted
        )
        guard status == kCCSuccess else { return nil }
        return Data(bytes: outBuffer, count: numBytesDecrypted)
    }
}
