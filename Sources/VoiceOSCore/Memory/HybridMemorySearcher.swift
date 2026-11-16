import Foundation

public struct HybridScoredItem: Identifiable, Sendable, Equatable {
    public let id: String
    public let item: StructuredMemoryItem
    public let hybridScore: Double
    public let keywordScore: Double
    public let semanticScore: Double
    public let recencyScore: Double
    
    public init(
        item: StructuredMemoryItem,
        hybridScore: Double,
        keywordScore: Double,
        semanticScore: Double,
        recencyScore: Double
    ) {
        self.id = item.id
        self.item = item
        self.hybridScore = hybridScore
        self.keywordScore = keywordScore
        self.semanticScore = semanticScore
        self.recencyScore = recencyScore
    }
}

public struct PendingMemoryConsent: Sendable, Equatable {
    public let id: String
    public let content: String
    public let category: String
    public let key: String?
    public let tags: [String]
    public let proposedAt: Date
    
    public init(
        id: String = UUID().uuidString,
        content: String,
        category: String = "preference",
        key: String? = nil,
        tags: [String] = [],
        proposedAt: Date = Date()
    ) {
        self.id = id
        self.content = content
        self.category = category
        self.key = key
        self.tags = tags
        self.proposedAt = proposedAt
    }
}

public final class HybridMemorySearcher: @unchecked Sendable {
    public static let shared = HybridMemorySearcher()
    
    private let lock = NSLock()
    private let autoRememberKey = "voiceos.memory.auto_remember_simple_preferences"
    private var pendingConsent: PendingMemoryConsent? = nil
    
    public var autoRememberSimplePreferences: Bool {
        get {
            // OFF by default as required by specification
            return UserDefaults.standard.bool(forKey: autoRememberKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: autoRememberKey)
        }
    }
    
    private init() {}
    
    // MARK: - Hybrid Search (FTS5 + Semantic Vector + Recency Weight)
    
    public func searchHybrid(
        query: String,
        accountId: String = "local_default",
        limit: Int = 5
    ) async -> [HybridScoredItem] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return [] }
        
        // 1. Keyword search via FTS5
        let ftsHits = UnifiedMemoryDatabase.shared.searchFacts(keyword: clean, limit: 20)
        let ftsMap = Dictionary(uniqueKeysWithValues: ftsHits.enumerated().map { ($0.element.id, 1.0 - (Double($0.offset) / Double(max(1, ftsHits.count)))) })
        
        // 2. Fetch all active facts for semantic vector scoring
        let allFacts = UnifiedMemoryDatabase.shared.allActiveFacts()
        guard !allFacts.isEmpty else { return [] }
        
        // 3. Generate query embedding
        let queryVector = await LocalEmbeddingProvider.shared.embed(clean)
        let now = Date()
        
        var scored: [HybridScoredItem] = []
        
        for item in allFacts {
            // Semantic cosine similarity
            let itemVector = await LocalEmbeddingProvider.shared.embed(item.content)
            let semanticSim = max(0.0, min(1.0, LocalEmbeddingProvider.shared.cosineSimilarity(queryVector, itemVector)))
            
            // FTS5 Keyword score
            let kwScore = ftsMap[item.id] ?? 0.0
            
            // Recency score (30-day exponential half-life)
            let ageSeconds = max(0.0, now.timeIntervalSince(item.updatedAt))
            let ageDays = ageSeconds / 86400.0
            let recencyScore = exp(-ageDays / 30.0)
            
            // Combined hybrid weight: 45% semantic, 40% keyword, 15% recency
            let combined = (0.45 * semanticSim) + (0.40 * kwScore) + (0.15 * recencyScore)
            
            if combined >= 0.10 {
                let scoredItem = HybridScoredItem(
                    item: item,
                    hybridScore: combined,
                    keywordScore: kwScore,
                    semanticScore: semanticSim,
                    recencyScore: recencyScore
                )
                scored.append(scoredItem)
            }
        }
        
        // Sort descending by hybrid score and take top limit
        let sorted = scored.sorted { $0.hybridScore > $1.hybridScore }
        return Array(sorted.prefix(limit))
    }
    
    // MARK: - Consent Management (Explicit "remember" vs "Do you want me to remember that?")
    
    public func proposeFactWithConsent(content: String, category: String, key: String? = nil, tags: [String] = []) -> (savedImmediately: Bool, confirmationPrompt: String?) {
        lock.lock()
        defer { lock.unlock() }
        
        // Instruction rejection check
        if MemoryStore.isInstructionLikeMemory(content) {
            return (false, "Rejected: I cannot store instructions that alter safety rules or approvals.")
        }
        
        // If user enabled auto-remember simple preferences, save immediately
        if autoRememberSimplePreferences {
            _ = UnifiedMemoryDatabase.shared.saveFact(category: category, key: key, content: content, provenanceType: "system_inferred", tags: tags)
            return (true, nil)
        }
        
        // Otherwise queue pending consent and return confirmation question
        let pending = PendingMemoryConsent(content: content, category: category, key: key, tags: tags)
        self.pendingConsent = pending
        let prompt = "Do you want me to remember that \(content)?"
        return (false, prompt)
    }
    
    public func hasPendingConsent() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return pendingConsent != nil
    }
    
    public func resolvePendingConsent(userAffirmation: Bool) -> (confirmed: Bool, rememberedContent: String?) {
        lock.lock()
        defer { lock.unlock() }
        guard let pending = pendingConsent else {
            return (false, nil)
        }
        self.pendingConsent = nil
        
        if userAffirmation {
            _ = UnifiedMemoryDatabase.shared.saveFact(
                category: pending.category,
                key: pending.key,
                content: pending.content,
                provenanceType: "user_confirmed",
                tags: pending.tags
            )
            return (true, pending.content)
        } else {
            return (false, nil)
        }
    }
    
    // MARK: - Correction & Supersede Engine
    
    public func applyCorrection(
        originalFactId: String?,
        oldValue: String,
        newValue: String,
        key: String?,
        category: String = "preference",
        reason: String? = nil
    ) -> String {
        // 1. Save new fact with key-based superseding
        let newId = UnifiedMemoryDatabase.shared.saveFact(
            category: category,
            key: key,
            content: newValue,
            provenanceType: "user_correction",
            tags: ["correction"]
        )
        
        // 2. If originalFactId was explicitly passed, mark it superseded
        if let origId = originalFactId {
            UnifiedMemoryDatabase.shared.forgetFact(id: origId)
        }
        
        return newId
    }
}
