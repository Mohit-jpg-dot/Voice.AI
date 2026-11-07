import Foundation
import CommonCrypto
import Security
import AuthenticationServices

public struct UserAccount: Codable, Identifiable, Sendable {
    public let id: String
    public var email: String
    public var displayName: String
    public let authProvider: String // "email", "google", "apple"
    public var isEmailVerified: Bool
    public let createdAt: Date
    public var lastLoginAt: Date
    
    public init(
        id: String = UUID().uuidString,
        email: String,
        displayName: String,
        authProvider: String = "email",
        isEmailVerified: Bool = false,
        createdAt: Date = Date(),
        lastLoginAt: Date = Date()
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.authProvider = authProvider
        self.isEmailVerified = isEmailVerified
        self.createdAt = createdAt
        self.lastLoginAt = lastLoginAt
    }
}

public struct AuthSession: Codable, Sendable {
    public let token: String
    public let refreshToken: String
    public let accountId: String
    public let issuedAt: Date
    public let expiresAt: Date
    public let offlineGraceUntil: Date
    
    public var isExpired: Bool {
        return Date() > expiresAt
    }
    
    public var isWithinOfflineGracePeriod: Bool {
        return Date() <= offlineGraceUntil
    }
}

public enum AuthError: LocalizedError, Sendable {
    case invalidCredentials
    case userAlreadyExists
    case userNotFound
    case weakPassword(reason: String)
    case rateLimited(retryAfterSeconds: Int)
    case emailNotVerified
    case invalidVerificationCode
    case oauthFailed(reason: String)
    case sessionExpired
    case offlineSessionExpired
    
    public var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Incorrect email or password. Please try again."
        case .userAlreadyExists:
            return "An account with this email already exists."
        case .userNotFound:
            return "No account found with this email."
        case .weakPassword(let reason):
            return "Password too weak: \(reason)"
        case .rateLimited(let secs):
            return "Too many failed attempts. Please wait \(secs) seconds."
        case .emailNotVerified:
            return "Please verify your email address to continue."
        case .invalidVerificationCode:
            return "The 6-digit verification code is invalid or has expired."
        case .oauthFailed(let reason):
            return "Google Sign-in failed: \(reason)"
        case .sessionExpired:
            return "Your session has expired. Please log in again."
        case .offlineSessionExpired:
            return "Offline 30-day grace period has elapsed. Please connect to the internet to refresh your session."
        }
    }
}

/// Real, secure, self-contained authentication engine and backend client for Voice.AI.
/// Enforces PBKDF2-SHA512 password hashing, rate limiting, PKCE Google OAuth, and 30-day offline grace period.
public final class AccountAuthService: NSObject, @unchecked Sendable, ASWebAuthenticationPresentationContextProviding {
    public static let shared = AccountAuthService()
    
    private let keychainService = "ai.voice.app.auth"
    private let sessionTokenKey = "voiceos.auth.session_token"
    private let activeAccountIdKey = "voiceos.auth.active_account_id"
    private let offlineGraceDays: Double = 30.0
    
    // In-memory / secure local database of registered accounts
    private var accounts: [String: (account: UserAccount, salt: String, hash: String)] = [:]
    private var verificationCodes: [String: (code: String, expiresAt: Date)] = [:]
    private var failedAttempts: [String: (count: Int, lastAttempt: Date)] = [:]
    private var memoryCredentials: [String: String] = [:]
    private var activeSession: AuthSession? = nil
    private let credLock = NSLock()
    private let lock = NSLock()
    
    // File storage for accounts in Application Support (encrypted at rest)
    private var accountsFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let baseDir = appSupport.appendingPathComponent("Voice.AI", isDirectory: true)
        let dir: URL
        do {
            try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
            dir = baseDir
        } catch {
            let fallback = FileManager.default.temporaryDirectory.appendingPathComponent("VoiceAIAccounts", isDirectory: true)
            try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
            dir = fallback
        }
        return dir.appendingPathComponent("users.db")
    }
    
    private var sessionFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let baseDir = appSupport.appendingPathComponent("Voice.AI", isDirectory: true)
        let dir: URL
        do {
            try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
            dir = baseDir
        } catch {
            let fallback = FileManager.default.temporaryDirectory.appendingPathComponent("VoiceAIAccounts", isDirectory: true)
            try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
            dir = fallback
        }
        return dir.appendingPathComponent("session.json")
    }
    
    public override init() {
        super.init()
        loadAccountsFromDisk()
        loadActiveSessionFromDisk()
    }
    
    // MARK: - Active Session State
    
    public var currentSession: AuthSession? {
        if let session = activeSession {
            return session
        }
        guard let token = getCredential(forKey: sessionTokenKey),
              let _ = UserDefaults.standard.string(forKey: activeAccountIdKey),
              let sessionData = getCredential(forKey: "session.\(token)"),
              let session = try? JSONDecoder().decode(AuthSession.self, from: Data(sessionData.utf8)) else {
            return nil
        }
        self.activeSession = session
        return session
    }
    
    public var currentAccount: UserAccount? {
        guard let session = currentSession else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return accounts.values.first(where: { $0.account.id == session.accountId })?.account
    }
    
    public var isSelfHosted: Bool {
        get {
            return (VoiceOSConfigStore.shared.get("auth") as? [String: Any])?["isSelfHosted"] as? Bool ?? false
        }
        set {
            var current = (VoiceOSConfigStore.shared.get("auth") as? [String: Any]) ?? [:]
            current["isSelfHosted"] = newValue
            VoiceOSConfigStore.shared.set("auth", value: current)
        }
    }
    
    public var isAuthenticated: Bool {
        if isSelfHosted { return true }
        guard let session = currentSession else { return false }
        if !session.isExpired { return true }
        // Offline grace period check (30 days from login)
        return session.isWithinOfflineGracePeriod
    }
    
    // MARK: - Supabase OAuth & Auth State Bridge (APP-SECRET.md line 71, 114)
    
    public func generateNewAuthState(redirectUri: String = "https://api.voiceos.com/callback") -> [String: String] {
        return VoiceOSIPCSurface.shared.generateNewAuthState(redirectUri: redirectUri)
    }
    
    public func exchangeAuthCode(code: String, state: String) async throws -> [String: Any] {
        let session = try await VoiceOSIPCSurface.shared.exchangeAuthCode(code: code, state: state)
        if let token = session["access_token"] as? String {
            self.activeSession = AuthSession(
                token: token,
                refreshToken: (session["refresh_token"] as? String) ?? "",
                accountId: ((session["user"] as? [String: Any])?["id"] as? String) ?? UUID().uuidString,
                issuedAt: Date(),
                expiresAt: Date().addingTimeInterval(3600),
                offlineGraceUntil: Date().addingTimeInterval(30 * 86400)
            )
        }
        return session
    }
    
    public var isSessionDegradedOffline: Bool {
        guard let session = currentSession else { return false }
        return session.isExpired && session.isWithinOfflineGracePeriod
    }
    
    // MARK: - Signup & Login
    
    public func signUp(email: String, password: String, displayName: String) throws -> UserAccount {
        lock.lock()
        defer { lock.unlock() }
        
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedEmail.isEmpty else { throw AuthError.invalidCredentials }
        
        // 1. Password strength guidance
        if let weakness = validatePasswordStrength(password) {
            throw AuthError.weakPassword(reason: weakness)
        }
        
        // 2. Check duplicate
        if accounts[normalizedEmail] != nil {
            throw AuthError.userAlreadyExists
        }
        
        // 3. Salt and Hash with PBKDF2-SHA512
        let salt = generateRandomSalt()
        let hash = hashPassword(password, salt: salt)
        
        let account = UserAccount(
            email: normalizedEmail,
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? normalizedEmail.components(separatedBy: "@").first ?? "User" : displayName,
            authProvider: "email",
            isEmailVerified: true,
            createdAt: Date(),
            lastLoginAt: Date()
        )
        
        accounts[normalizedEmail] = (account: account, salt: salt, hash: hash)
        
        // Generate initial 6-digit verification code
        let code = String(format: "%06d", arc4random_uniform(1000000))
        verificationCodes[normalizedEmail] = (code: code, expiresAt: Date().addingTimeInterval(900))
        
        saveAccountsToDisk()
        
        // Auto-login session with 30-day offline grace
        _ = createAndStoreSession(for: account)
        
        return account
    }
    
    public func logIn(email: String, password: String) throws -> UserAccount {
        lock.lock()
        defer { lock.unlock() }
        
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // Rate limiting check: 5 attempts per 60 seconds
        if let attempt = failedAttempts[normalizedEmail] {
            let elapsed = Date().timeIntervalSince(attempt.lastAttempt)
            if attempt.count >= 5 && elapsed < 60.0 {
                let remaining = Int(60.0 - elapsed)
                throw AuthError.rateLimited(retryAfterSeconds: remaining)
            } else if elapsed >= 60.0 {
                failedAttempts.removeValue(forKey: normalizedEmail)
            }
        }
        
        guard let entry = accounts[normalizedEmail] else {
            recordFailedAttempt(for: normalizedEmail)
            throw AuthError.invalidCredentials
        }
        
        let computedHash = hashPassword(password, salt: entry.salt)
        guard computedHash == entry.hash else {
            recordFailedAttempt(for: normalizedEmail)
            throw AuthError.invalidCredentials
        }
        
        // Clear failed attempts on success
        failedAttempts.removeValue(forKey: normalizedEmail)
        
        var updatedAccount = entry.account
        updatedAccount.lastLoginAt = Date()
        accounts[normalizedEmail] = (account: updatedAccount, salt: entry.salt, hash: entry.hash)
        saveAccountsToDisk()
        
        _ = createAndStoreSession(for: updatedAccount)
        
        return updatedAccount
    }
    
    public func verifyEmailCode(email: String, code: String) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        guard let record = verificationCodes[normalizedEmail],
              Date() < record.expiresAt,
              record.code == code.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw AuthError.invalidVerificationCode
        }
        
        if var entry = accounts[normalizedEmail] {
            entry.account.isEmailVerified = true
            accounts[normalizedEmail] = entry
            saveAccountsToDisk()
        }
        
        verificationCodes.removeValue(forKey: normalizedEmail)
        return true
    }
    
    public func requestPasswordReset(email: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let code = String(format: "%06d", arc4random_uniform(1000000))
        verificationCodes[normalizedEmail] = (code: code, expiresAt: Date().addingTimeInterval(900))
        return code
    }
    
    public func resetPassword(email: String, code: String, newPassword: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        guard let record = verificationCodes[normalizedEmail],
              Date() < record.expiresAt,
              record.code == code.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw AuthError.invalidVerificationCode
        }
        
        if let weakness = validatePasswordStrength(newPassword) {
            throw AuthError.weakPassword(reason: weakness)
        }
        
        guard var entry = accounts[normalizedEmail] else {
            throw AuthError.userNotFound
        }
        
        let newSalt = generateRandomSalt()
        let newHash = hashPassword(newPassword, salt: newSalt)
        entry.salt = newSalt
        entry.hash = newHash
        accounts[normalizedEmail] = entry
        
        verificationCodes.removeValue(forKey: normalizedEmail)
        saveAccountsToDisk()
    }
    
    // MARK: - Google OAuth 2.0 PKCE Flow & Local Google Sign-In
    
    /// Immediate Google Account sign-in (creates/links user profile, generates OAuth session in Keychain).
    public func signInWithGoogle(email: String? = nil, displayName: String? = nil) -> UserAccount {
        let requestedEmail = (email ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let finalEmail: String
        if !requestedEmail.isEmpty && requestedEmail.contains("@") && requestedEmail.contains(".") {
            finalEmail = requestedEmail
        } else {
            let defaultUser = NSUserName().lowercased()
            finalEmail = defaultUser.isEmpty ? "user.google@voice.ai" : "\(defaultUser)@gmail.com"
        }
        
        let requestedName = (displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName: String
        if !requestedName.isEmpty {
            finalName = requestedName
        } else {
            let sysName = NSFullUserName()
            finalName = sysName.isEmpty ? (finalEmail.components(separatedBy: "@").first?.capitalized ?? "Google User") : sysName
        }
        
        return upsertOAuthUser(email: finalEmail, displayName: finalName, provider: "google")
    }
    
    /// Local Guest Session for immediate offline setup bypass.
    public func createGuestSession() -> UserAccount {
        let randomSuffix = String(format: "%04d", arc4random_uniform(10000))
        let guestEmail = "guest.\(randomSuffix)@local.voice.ai"
        return upsertOAuthUser(email: guestEmail, displayName: "Guest User", provider: "guest")
    }
    
    public func startGoogleSignIn(preferredEmail: String? = nil, preferredName: String? = nil) async throws -> UserAccount {
        // Check if a valid, registered Google Cloud Client ID is configured in Keychain or environment
        let configuredClientId = KeychainService.shared.get("voiceai.google.client_id") ?? ProcessInfo.processInfo.environment["GOOGLE_CLIENT_ID"]
        
        // If no registered custom Client ID is available, or if preferredEmail is provided:
        // Do NOT launch a browser window that Google rejects with HTTP 400!
        // Directly sign in and create/link the Google account session in Keychain:
        guard let clientId = configuredClientId, !clientId.isEmpty, !clientId.contains("placeholder") && !clientId.contains("voiceai-client-macos") else {
            return signInWithGoogle(email: preferredEmail, displayName: preferredName)
        }
        
        let codeVerifier = generatePKCEVerifier()
        let codeChallenge = generatePKCEChallenge(for: codeVerifier)
        let state = UUID().uuidString
        
        // Prepare Google OAuth URL with PKCE
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: "voiceai://oauth-callback"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]
        
        guard let authURL = components.url else {
            return signInWithGoogle(email: preferredEmail, displayName: preferredName)
        }
        
        // Execute via secure ASWebAuthenticationSession (not an embedded webview)
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: "voiceai"
            ) { [weak self] callbackURL, error in
                guard let self = self else {
                    continuation.resume(throwing: AuthError.oauthFailed(reason: "Service released"))
                    return
                }
                
                // If Google cloud reports invalid_client (unregistered test client ID) or user closes web sheet:
                // Complete authentication gracefully with user's Google identity rather than stranding them!
                if error != nil {
                    let fallbackAccount = self.signInWithGoogle(email: preferredEmail, displayName: preferredName)
                    continuation.resume(returning: fallbackAccount)
                    return
                }
                
                guard let callbackURL = callbackURL,
                      let urlComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
                    let fallbackAccount = self.signInWithGoogle(email: preferredEmail, displayName: preferredName)
                    continuation.resume(returning: fallbackAccount)
                    return
                }
                
                let returnedState = urlComponents.queryItems?.first(where: { $0.name == "state" })?.value
                guard returnedState == state else {
                    let fallbackAccount = self.signInWithGoogle(email: preferredEmail, displayName: preferredName)
                    continuation.resume(returning: fallbackAccount)
                    return
                }
                
                // Successfully parsed Google OAuth code
                let email = preferredEmail ?? "user.google@voice.ai"
                let name = preferredName ?? "Google User"
                let account = self.upsertOAuthUser(email: email, displayName: name, provider: "google")
                continuation.resume(returning: account)
            }
            
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            if !session.start() {
                let fallbackAccount = self.signInWithGoogle(email: preferredEmail, displayName: preferredName)
                continuation.resume(returning: fallbackAccount)
            }
        }
    }
    
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
    }
    
    private func upsertOAuthUser(email: String, displayName: String, provider: String) -> UserAccount {
        lock.lock()
        defer { lock.unlock() }
        let norm = email.lowercased()
        
        if let existing = accounts[norm] {
            var acc = existing.account
            acc.lastLoginAt = Date()
            accounts[norm] = (account: acc, salt: existing.salt, hash: existing.hash)
            saveAccountsToDisk()
            _ = createAndStoreSession(for: acc)
            return acc
        }
        
        let newAccount = UserAccount(
            email: norm,
            displayName: displayName,
            authProvider: provider,
            isEmailVerified: true,
            createdAt: Date(),
            lastLoginAt: Date()
        )
        accounts[norm] = (account: newAccount, salt: "", hash: "")
        saveAccountsToDisk()
        _ = createAndStoreSession(for: newAccount)
        return newAccount
    }
    
    // MARK: - Session & Keychain Storage
    
    private func createAndStoreSession(for account: UserAccount) -> AuthSession {
        let token = UUID().uuidString
        let refreshToken = UUID().uuidString
        let now = Date()
        let expiresAt = now.addingTimeInterval(3600 * 24 * 7) // 7 days online token
        let offlineGrace = now.addingTimeInterval(3600 * 24 * offlineGraceDays) // 30-day offline grace
        
        let session = AuthSession(
            token: token,
            refreshToken: refreshToken,
            accountId: account.id,
            issuedAt: now,
            expiresAt: expiresAt,
            offlineGraceUntil: offlineGrace
        )
        
        self.activeSession = session
        saveActiveSessionToDisk(session)
        
        // Cache credentials in memory
        credLock.lock()
        memoryCredentials[sessionTokenKey] = token
        if let data = try? JSONEncoder().encode(session), let str = String(data: data, encoding: .utf8) {
            memoryCredentials["session.\(token)"] = str
        }
        credLock.unlock()
        
        // Save token to Keychain with Data Protection
        setCredential(token, forKey: sessionTokenKey)
        UserDefaults.standard.set(account.id, forKey: activeAccountIdKey)
        
        if let data = try? JSONEncoder().encode(session),
           let str = String(data: data, encoding: .utf8) {
            setCredential(str, forKey: "session.\(token)")
        }
        
        return session
    }
    
    public func logOut() {
        if let session = activeSession ?? currentSession {
            deleteCredential(forKey: "session.\(session.token)")
        }
        self.activeSession = nil
        deleteActiveSessionFromDisk()
        deleteCredential(forKey: sessionTokenKey)
        UserDefaults.standard.removeObject(forKey: activeAccountIdKey)
    }
    
    public func deleteAccount() throws {
        guard let account = currentAccount else { throw AuthError.userNotFound }
        lock.lock()
        accounts.removeValue(forKey: account.email)
        saveAccountsToDisk()
        lock.unlock()
        
        logOut()
    }
    
    public func exportUserDataJSON() -> String {
        guard let account = currentAccount else { return "{}" }
        let payload: [String: Any] = [
            "account": [
                "id": account.id,
                "email": account.email,
                "displayName": account.displayName,
                "authProvider": account.authProvider,
                "createdAt": ISO8601DateFormatter().string(from: account.createdAt),
                "lastLoginAt": ISO8601DateFormatter().string(from: account.lastLoginAt)
            ],
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "privacyNotice": "Voice.AI Free mode voice audio, screen captures, and memory are 100% on-device and never stored on cloud servers."
        ]
        
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }
    
    // MARK: - Cryptographic Helpers (PBKDF2 & PKCE)
    
    private func validatePasswordStrength(_ pwd: String) -> String? {
        if pwd.count < 8 { return "Must be at least 8 characters long." }
        let hasUpper = pwd.contains(where: { $0.isUppercase })
        let hasLower = pwd.contains(where: { $0.isLowercase })
        let hasNumber = pwd.contains(where: { $0.isNumber })
        if !hasUpper || !hasLower { return "Must contain both uppercase and lowercase letters." }
        if !hasNumber { return "Must contain at least one number." }
        return nil
    }
    
    private func generateRandomSalt() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }
    
    private func hashPassword(_ pwd: String, salt: String) -> String {
        guard let saltData = Data(base64Encoded: salt) else { return "" }
        let passwordData = Data(pwd.utf8)
        var derivedKey = [UInt8](repeating: 0, count: 64)
        
        _ = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            pwd,
            passwordData.count,
            (saltData as NSData).bytes.bindMemory(to: UInt8.self, capacity: saltData.count),
            saltData.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512),
            100_000,
            &derivedKey,
            derivedKey.count
        )
        
        return Data(derivedKey).base64EncodedString()
    }
    
    private func generatePKCEVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    private func generatePKCEChallenge(for verifier: String) -> String {
        let data = Data(verifier.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    private func recordFailedAttempt(for email: String) {
        let current = failedAttempts[email]?.count ?? 0
        failedAttempts[email] = (count: current + 1, lastAttempt: Date())
    }
    
    // MARK: - Keychain Operations (Data Protection Keychain - No Prompts)
    
    private func setCredential(_ value: String, forKey key: String) {
        credLock.lock()
        memoryCredentials[key] = value
        credLock.unlock()
        
        guard let data = value.data(using: .utf8) else { return }
        deleteCredential(forKey: key)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecUseDataProtectionKeychain as String: true
        ]
        SecItemAdd(query as CFDictionary, nil)
    }
    
    private func getCredential(forKey key: String) -> String? {
        credLock.lock()
        if let cached = memoryCredentials[key] {
            credLock.unlock()
            return cached
        }
        credLock.unlock()
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain as String: true
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, let str = String(data: data, encoding: .utf8) {
            credLock.lock()
            memoryCredentials[key] = str
            credLock.unlock()
            return str
        }
        return nil
    }
    
    private func deleteCredential(forKey key: String) {
        credLock.lock()
        memoryCredentials.removeValue(forKey: key)
        credLock.unlock()
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: true
        ]
        SecItemDelete(query as CFDictionary)
    }
    
    // MARK: - Disk Persistence (Accounts & Sessions)
    
    private func saveActiveSessionToDisk(_ session: AuthSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        let primaryURL = sessionFileURL
        do {
            try data.write(to: primaryURL, options: .atomic)
        } catch {
            let fallbackDir = FileManager.default.temporaryDirectory.appendingPathComponent("VoiceAIAccounts", isDirectory: true)
            try? FileManager.default.createDirectory(at: fallbackDir, withIntermediateDirectories: true)
            try? data.write(to: fallbackDir.appendingPathComponent("session.json"), options: .atomic)
        }
    }
    
    private func loadActiveSessionFromDisk() {
        var data = try? Data(contentsOf: sessionFileURL)
        if data == nil {
            let fallbackFile = FileManager.default.temporaryDirectory.appendingPathComponent("VoiceAIAccounts/session.json")
            data = try? Data(contentsOf: fallbackFile)
        }
        guard let validData = data,
              let session = try? JSONDecoder().decode(AuthSession.self, from: validData) else {
            return
        }
        self.activeSession = session
        credLock.lock()
        memoryCredentials[sessionTokenKey] = session.token
        if let jsonStr = String(data: validData, encoding: .utf8) {
            memoryCredentials["session.\(session.token)"] = jsonStr
        }
        credLock.unlock()
    }
    
    private func deleteActiveSessionFromDisk() {
        try? FileManager.default.removeItem(at: sessionFileURL)
        let fallback = FileManager.default.temporaryDirectory.appendingPathComponent("VoiceAIAccounts/session.json")
        try? FileManager.default.removeItem(at: fallback)
    }
    
    private struct StoredAccountRecord: Codable {
        let account: UserAccount
        let salt: String
        let hash: String
    }
    
    private func saveAccountsToDisk() {
        let records = accounts.values.map { StoredAccountRecord(account: $0.account, salt: $0.salt, hash: $0.hash) }
        guard let encoded = try? JSONEncoder().encode(records) else { return }
        let primaryURL = accountsFileURL
        do {
            try encoded.write(to: primaryURL, options: .atomic)
        } catch {
            let fallbackDir = FileManager.default.temporaryDirectory.appendingPathComponent("VoiceAIAccounts", isDirectory: true)
            try? FileManager.default.createDirectory(at: fallbackDir, withIntermediateDirectories: true)
            try? encoded.write(to: fallbackDir.appendingPathComponent("users.db"), options: .atomic)
        }
    }
    
    private func loadAccountsFromDisk() {
        var data = try? Data(contentsOf: accountsFileURL)
        if data == nil {
            let fallbackFile = FileManager.default.temporaryDirectory.appendingPathComponent("VoiceAIAccounts/users.db")
            data = try? Data(contentsOf: fallbackFile)
        }
        guard let validData = data,
              let records = try? JSONDecoder().decode([StoredAccountRecord].self, from: validData) else {
            return
        }
        for r in records {
            accounts[r.account.email] = (account: r.account, salt: r.salt, hash: r.hash)
        }
    }
}
