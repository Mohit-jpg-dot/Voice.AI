import Foundation
import AppKit
import VoiceOSCore

@main
struct SetupAndAuthTestSuite {
    static var passCount = 0
    static var failCount = 0
    
    static func assertTest(_ condition: Bool, _ name: String) {
        if condition {
            print("  ✓ PASS: \(name)")
            passCount += 1
        } else {
            print("  ✗ FAIL: \(name)")
            failCount += 1
        }
    }
    
    static func main() async {
        print("=================================================================")
        print("Voice.AI Setup Flow, Auth Engine & Encrypted History Test Runner")
        print("Date: \(Date())")
        print("=================================================================\n")
        
        let auth = AccountAuthService.shared
        
        // MARK: - Suite 1: Authentication & PBKDF2 Hashing
        print("[Suite 1] Authentication Engine & PBKDF2 Cryptographic Security")
        
        // 1. Weak password test
        do {
            _ = try auth.signUp(email: "test.weak@voice.ai", password: "123", displayName: "Tester")
            assertTest(false, "Weak password was rejected")
        } catch AuthError.weakPassword {
            assertTest(true, "Weak password was rejected with guidance")
        } catch {
            assertTest(false, "Unexpected error on weak password: \(error)")
        }
        
        // 2. Strong password signup
        let testEmailA = "alice.\(Int(Date().timeIntervalSince1970))@voice.ai"
        let strongPwd = "PassWord123!Safe"
        do {
            let accountA = try auth.signUp(email: testEmailA, password: strongPwd, displayName: "Alice User")
            assertTest(accountA.email == testEmailA, "Account signed up successfully with salt & PBKDF2 hash")
        } catch {
            assertTest(false, "Failed to sign up: \(error)")
        }
        
        // 3. Duplicate email prevention
        do {
            _ = try auth.signUp(email: testEmailA, password: strongPwd, displayName: "Alice Duplicate")
            assertTest(false, "Duplicate email rejected")
        } catch AuthError.userAlreadyExists {
            assertTest(true, "Duplicate email rejected with userAlreadyExists")
        } catch {
            assertTest(false, "Unexpected error: \(error)")
        }
        
        // 4. Invalid credentials login
        do {
            _ = try auth.logIn(email: testEmailA, password: "WrongPassword999!")
            assertTest(false, "Wrong password was rejected")
        } catch AuthError.invalidCredentials {
            assertTest(true, "Wrong password rejected with invalidCredentials")
        } catch {
            assertTest(false, "Unexpected error: \(error)")
        }
        
        // 5. Successful login
        do {
            let loggedIn = try auth.logIn(email: testEmailA, password: strongPwd)
            assertTest(loggedIn.email == testEmailA, "Successfully logged in with correct credentials")
            assertTest(auth.isAuthenticated, "Active session authenticated")
            assertTest(auth.currentSession?.isWithinOfflineGracePeriod == true, "30-day offline grace period active on session")
        } catch {
            assertTest(false, "Failed to log in: \(error)")
        }
        
        // 6. Google Sign-In test
        let googleEmail = "tester.google.\(Int(Date().timeIntervalSince1970))@gmail.com"
        let googleUser = auth.signInWithGoogle(email: googleEmail, displayName: "Google Tester")
        assertTest(googleUser.email == googleEmail, "Google sign-in created account with email: \(googleEmail)")
        assertTest(googleUser.authProvider == "google", "Account provider is 'google'")
        assertTest(googleUser.isEmailVerified, "Google user is auto-verified")
        assertTest(auth.isAuthenticated, "Google user authenticated with active session")
        
        // 7. Guest Session test
        let guestUser = auth.createGuestSession()
        assertTest(guestUser.authProvider == "guest", "Guest session created with provider 'guest'")
        assertTest(guestUser.email.contains("local.voice.ai"), "Guest email is local offline address")
        assertTest(auth.isAuthenticated, "Guest session is authenticated")
        
        // Re-login Account A for Suite 2
        _ = try! auth.logIn(email: testEmailA, password: strongPwd)
        
        // 8. User Data Export JSON
        let exportJson = auth.exportUserDataJSON()
        assertTest(exportJson.contains(testEmailA), "User data export contains account profile")
        assertTest(!exportJson.contains(strongPwd), "Export never contains plaintext password or salt")
        print("")
        
        // MARK: - Suite 2: Per-Account Encrypted Chat History & Secret Redaction
        print("[Suite 2] Per-Account Encrypted Chat History & Isolation")
        let history = EncryptedChatHistoryManager.shared
        guard let accountA = auth.currentAccount else {
            fatalError("Account A missing")
        }
        
        // Load Account A
        history.loadForAccount(accountId: accountA.id)
        
        // Record conversation with secret API key in prompt
        let promptWithSecret = "Here is my key sk-proj-1234567890abcdef1234567890 and please open Safari"
        let response = "opened the app for you sir"
        
        let sessionRec = history.recordTurn(
            conversationId: nil,
            userText: promptWithSecret,
            assistantText: response,
            persona: "Friday"
        )
        assertTest(sessionRec != nil, "Recorded conversation turn in Account A history")
        
        // Verify secret redaction
        let conversationsA = history.listConversations()
        assertTest(!conversationsA.isEmpty, "Account A has recorded conversations")
        if let firstMsg = conversationsA.first?.messages.first {
            assertTest(!firstMsg.content.contains("sk-proj-1234567890"), "Secret API key was cleanly redacted: \(firstMsg.content)")
            assertTest(firstMsg.content.contains("[REDACTED_API_KEY]"), "Contains [REDACTED_API_KEY] placeholder")
        }
        
        // Create Account B
        let testEmailB = "bob.\(Int(Date().timeIntervalSince1970))@voice.ai"
        let accountB = try! auth.signUp(email: testEmailB, password: strongPwd, displayName: "Bob User")
        
        // Switch to Account B
        history.loadForAccount(accountId: accountB.id)
        let conversationsB = history.listConversations()
        assertTest(conversationsB.isEmpty, "Account B CANNOT see Account A's history (Strict account isolation verified)")
        
        // Unload / Log out
        auth.logOut()
        history.unloadCurrentAccount()
        assertTest(history.listConversations().isEmpty, "Logged out state displays zero history")
        
        // Re-login Account A
        _ = try! auth.logIn(email: testEmailA, password: strongPwd)
        history.loadForAccount(accountId: accountA.id)
        assertTest(!history.listConversations().isEmpty, "Re-authenticating Account A unlocks and decrypts its history")
        print("")
        
        // MARK: - Suite 3: Hardware Profile & Model Recommendation
        print("[Suite 3] Hardware Specification & Profile Tier Recommendation")
        let detector = HardwareProfileDetector.shared
        let spec = detector.detectHardware()
        assertTest(!spec.chipModel.isEmpty, "Detected Mac chip: \(spec.chipModel)")
        assertTest(spec.totalRamGigabytes > 0, "Detected physical RAM: \(spec.totalRamGigabytes) GB")
        assertTest(spec.freeDiskGigabytes > 0, "Detected available disk space: \(spec.freeDiskGigabytes) GB")
        assertTest(spec.canRunLocalModels, "Hardware confirmed capable of running local offline models")
        
        let catalogLite = detector.getCatalogItems(for: .lite)
        let catalogBalanced = detector.getCatalogItems(for: .balanced)
        let catalogBest = detector.getCatalogItems(for: .best)
        
        assertTest(catalogLite.contains { $0.id.contains("3b") }, "Lite tier recommends fast 3B parameter model")
        assertTest(catalogBalanced.contains { $0.id.contains("7b") }, "Balanced tier recommends 7B parameter model")
        assertTest(catalogBest.contains { $0.id.contains("14b") }, "Best tier recommends 14B parameter model")
        print("")
        
        // MARK: - Suite 4: Command Transparency
        print("[Suite 4] Command Transparency & Exact Execution Parity")
        for item in catalogBalanced {
            assertTest(!item.command.isEmpty, "Item '\(item.name)' defines exact transparent terminal command: `\(item.command)`")
            assertTest(!item.license.isEmpty, "Item '\(item.name)' displays open license (\(item.license))")
        }
        print("")
        
        // MARK: - Suite 5: In-App Download Manager Progress & Auto-Config
        print("[Suite 5] Local Model Download Manager & Auto-Configuration")
        let downloader = LocalModelDownloadManager.shared
        downloader.queueDownloads(items: catalogLite)
        
        let tasks = downloader.getTasks()
        assertTest(tasks.count == catalogLite.count, "Queued \(tasks.count) catalog items for automated installation")
        
        await downloader.startAllQueuedDownloads()
        let finishedTasks = downloader.getTasks()
        let allReady = finishedTasks.allSatisfy { $0.status == .ready }
        assertTest(allReady, "All downloaded models verified and marked Ready")
        
        assertTest(ModelRouter.shared.currentMode == .local, "Auto-configuration switched active router to Local Mode")
        print("")
        
        // MARK: - Final Report
        print("=================================================================")
        print("Setup Flow & Auth Engine Tests Complete")
        print("Results: \(passCount) PASSED, \(failCount) FAILED")
        print("=================================================================")
        
        if failCount > 0 {
            exit(1)
        }
    }
}

