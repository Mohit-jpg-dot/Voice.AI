import Foundation

/// ConnectRPC & Protobuf Schemas matching APP-SECRET.md line 90.
/// Generated typed schema models for cloud streaming, context capture, and voice session persistence.
public enum VoiceOSProtobuf {
    public static let package = "file_voiceos"
}

// 1. StreamMessageSchema
public struct StreamMessageSchema: Codable, Sendable {
    public let messageId: String
    public let conversationId: String
    public let chunkIndex: Int
    public let deltaText: String
    public let isFinal: Bool
    public let audioSampleRate: Int?
    public let latencyMs: Double?
    
    public init(
        messageId: String = UUID().uuidString,
        conversationId: String,
        chunkIndex: Int,
        deltaText: String,
        isFinal: Bool,
        audioSampleRate: Int? = 16000,
        latencyMs: Double? = nil
    ) {
        self.messageId = messageId
        self.conversationId = conversationId
        self.chunkIndex = chunkIndex
        self.deltaText = deltaText
        self.isFinal = isFinal
        self.audioSampleRate = audioSampleRate
        self.latencyMs = latencyMs
    }
}

// 2. ScreenshotContextSchema
public struct ScreenshotContextSchema: Codable, Sendable {
    public let captureTimestamp: String
    public let screenWidth: Double
    public let screenHeight: Double
    public let activeApplicationName: String
    public let focusedWindowBoundingBox: [Double]? // [x, y, width, height]
    public let base64JPEGData: String
    public let detectedTextBlocks: [String]
    
    public init(
        captureTimestamp: String = ISO8601DateFormatter().string(from: Date()),
        screenWidth: Double,
        screenHeight: Double,
        activeApplicationName: String,
        focusedWindowBoundingBox: [Double]? = nil,
        base64JPEGData: String,
        detectedTextBlocks: [String] = []
    ) {
        self.captureTimestamp = captureTimestamp
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
        self.activeApplicationName = activeApplicationName
        self.focusedWindowBoundingBox = focusedWindowBoundingBox
        self.base64JPEGData = base64JPEGData
        self.detectedTextBlocks = detectedTextBlocks
    }
}

// 3. MatchAppIntentRequestSchema
public struct MatchAppIntentRequestSchema: Codable, Sendable {
    public let query: String
    public let frontmostApp: String?
    public let availableIntegrations: [String]
    public let userLocale: String
    
    public init(
        query: String,
        frontmostApp: String? = nil,
        availableIntegrations: [String] = [],
        userLocale: String = "auto"
    ) {
        self.query = query
        self.frontmostApp = frontmostApp
        self.availableIntegrations = availableIntegrations
        self.userLocale = userLocale
    }
}

// 4. ListVoiceSessionsRequestSchema
public struct ListVoiceSessionsRequestSchema: Codable, Sendable {
    public let userId: String
    public let pageLimit: Int
    public let cursorToken: String?
    public let filterMode: String?
    
    public init(userId: String, pageLimit: Int = 50, cursorToken: String? = nil, filterMode: String? = nil) {
        self.userId = userId
        self.pageLimit = pageLimit
        self.cursorToken = cursorToken
        self.filterMode = filterMode
    }
}

// 5. RecordVoiceSessionUsageRequestSchema
public struct RecordVoiceSessionUsageRequestSchema: Codable, Sendable {
    public let sessionId: String
    public let userId: String
    public let wordCount: Int
    public let durationSeconds: Double
    public let sttEngineUsed: String
    public let llmTokensUsed: Int
    public let metricsJSON: String
    
    public init(
        sessionId: String,
        userId: String,
        wordCount: Int,
        durationSeconds: Double,
        sttEngineUsed: String,
        llmTokensUsed: Int,
        metricsJSON: String
    ) {
        self.sessionId = sessionId
        self.userId = userId
        self.wordCount = wordCount
        self.durationSeconds = durationSeconds
        self.sttEngineUsed = sttEngineUsed
        self.llmTokensUsed = llmTokensUsed
        self.metricsJSON = metricsJSON
    }
}

// 6. UpdateVoiceSessionRequestSchema
public struct UpdateVoiceSessionRequestSchema: Codable, Sendable {
    public let sessionId: String
    public let title: String?
    public let isPinned: Bool?
    public let tags: [String]?
    
    public init(sessionId: String, title: String? = nil, isPinned: Bool? = nil, tags: [String]? = nil) {
        self.sessionId = sessionId
        self.title = title
        self.isPinned = isPinned
        self.tags = tags
    }
}

// 7. UpdateDictionaryItemRequestSchema
public struct UpdateDictionaryItemRequestSchema: Codable, Sendable {
    public let word: String
    public let replacement: String
    public let locale: String
    public let action: String // "add", "remove", "update"
    
    public init(word: String, replacement: String, locale: String = "en", action: String = "add") {
        self.word = word
        self.replacement = replacement
        self.locale = locale
        self.action = action
    }
}

// 8. ModeUpdateSchema
public struct ModeUpdateSchema: Codable, Sendable {
    public let previousMode: String
    public let newMode: String
    public let triggerKey: String
    public let timestamp: String
    
    public init(
        previousMode: String,
        newMode: String,
        triggerKey: String,
        timestamp: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.previousMode = previousMode
        self.newMode = newMode
        self.triggerKey = triggerKey
        self.timestamp = timestamp
    }
}

// 9. WordModificationSchema
public struct WordModificationSchema: Codable, Sendable {
    public let originalWord: String
    public let modifiedWord: String
    public let startIndex: Int
    public let endIndex: Int
    public let correctionType: String // "phonetic", "slang", "filler_removal", "punctuation"
    
    public init(
        originalWord: String,
        modifiedWord: String,
        startIndex: Int,
        endIndex: Int,
        correctionType: String
    ) {
        self.originalWord = originalWord
        self.modifiedWord = modifiedWord
        self.startIndex = startIndex
        self.endIndex = endIndex
        self.correctionType = correctionType
    }
}

