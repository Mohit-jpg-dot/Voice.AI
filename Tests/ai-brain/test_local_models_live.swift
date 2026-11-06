import Foundation
import AppKit
import VoiceOSCore

@main
struct LocalModelsLiveTestSuite {
    static var passCount = 0
    static var failCount = 0
    static var testReport: [String] = []
    static var bugsFound: [(title: String, severity: String, description: String, reproduction: String, fixOrStatus: String)] = []

    static func assertTest(_ condition: Bool, _ name: String, notes: String = "") {
        if condition {
            let msg = "  ✓ PASS: \(name)" + (notes.isEmpty ? "" : " (\(notes))")
            print(msg)
            testReport.append(msg)
            passCount += 1
        } else {
            let msg = "  ✗ FAIL: \(name)" + (notes.isEmpty ? "" : " (\(notes))")
            print(msg)
            testReport.append(msg)
            failCount += 1
        }
    }

    static func recordBug(title: String, severity: String, description: String, reproduction: String, fixOrStatus: String) {
        bugsFound.append((title: title, severity: severity, description: description, reproduction: reproduction, fixOrStatus: fixOrStatus))
    }

    static func main() async {
        print("=================================================================")
        print("Voice.AI Offline Local AI Models Deep Empirical Audit")
        print("Target Hardware: Apple Silicon (Unified Memory Architecture)")
        print("Models: Llama-3.2-3B (Brain) + LLaVA-7B (Eyes) + Kokoro-82M (Voice)")
        print("Timestamp: \(Date())")
        print("=================================================================\n")

        // Ensure Router is set to Local Mode
        ModelRouter.shared.currentMode = .local

        // -------------------------------------------------------------
        // SUITE 1: Local Model Files & Runtime Status Verification
        // -------------------------------------------------------------
        print("[SUITE 1] Local Model Files & Runtime Status Verification")
        let ollama = OllamaProvider(model: "llama3.2:3b", host: "http://localhost:11434")
        let isOllamaRunning = await ollama.isRunning()
        assertTest(isOllamaRunning, "Ollama daemon is active at http://localhost:11434")

        var installedOllamaModels: [OllamaModelInfo] = []
        do {
            installedOllamaModels = try await ollama.listLocalModels()
            let modelNames = installedOllamaModels.map { $0.name }
            print("  ℹ Ollama models discovered: \(modelNames.joined(separator: ", "))")
            
            let hasBrain = modelNames.contains(where: { $0.contains("llama3.2:3b") || $0.contains("llama3.2") })
            assertTest(hasBrain, "Llama-3.2-3B (The Brain) is installed in Ollama", notes: "Verified in /api/tags")
            if !hasBrain {
                recordBug(
                    title: "Llama-3.2-3B Missing in Ollama",
                    severity: "Critical",
                    description: "The Brain model (llama3.2:3b) was not found in Ollama tags.",
                    reproduction: "Run `curl http://localhost:11434/api/tags`",
                    fixOrStatus: "Run `ollama pull llama3.2:3b`"
                )
            }
            
            let hasEyes = modelNames.contains(where: { $0.contains("llava:7b") || $0.contains("llava") || $0.contains("llama3.2-vision") })
            assertTest(hasEyes, "LLaVA-7B / Vision (The Eyes) is installed in Ollama", notes: "Verified in /api/tags")
            if !hasEyes {
                recordBug(
                    title: "LLaVA-7B Vision Model Missing in Ollama",
                    severity: "High",
                    description: "Vision model (llava:7b) was not found in Ollama tags.",
                    reproduction: "Run `curl http://localhost:11434/api/tags`",
                    fixOrStatus: "Run `ollama pull llava:7b`"
                )
            }
        } catch {
            assertTest(false, "Failed to connect to Ollama: \(error.localizedDescription)")
            recordBug(
                title: "Ollama Connection Refused",
                severity: "Blocker",
                description: "Cannot connect to local Ollama HTTP API: \(error.localizedDescription)",
                reproduction: "Run `curl http://localhost:11434/api/tags`",
                fixOrStatus: "Launch Ollama app or run `ollama serve`"
            )
        }

        // Kokoro ONNX verification
        let kokoroPath = NSHomeDirectory() + "/.voiceos/models/kokoro.onnx"
        let kokoroExists = FileManager.default.fileExists(atPath: kokoroPath)
        var kokoroSize: Int64 = 0
        if let attrs = try? FileManager.default.attributesOfItem(atPath: kokoroPath),
           let s = attrs[.size] as? Int64 {
            kokoroSize = s
        }
        let kokoroValid = kokoroExists && kokoroSize > 1_000_000
        assertTest(kokoroValid, "Kokoro-82M ONNX model is verified on disk", notes: "Size: \(kokoroSize / 1024 / 1024) MB (\(kokoroSize) bytes) at \(kokoroPath)")
        if !kokoroValid {
            recordBug(
                title: "Kokoro-82M ONNX Model Missing or Incomplete",
                severity: "High",
                description: "kokoro.onnx at \(kokoroPath) is \(kokoroSize) bytes (expected ~86 MB).",
                reproduction: "Run `ls -lh ~/.voiceos/models/kokoro.onnx`",
                fixOrStatus: "Download via the Voice.AI Setup Dashboard or HuggingFace onnx-community repository."
            )
        }
        print("")

        // -------------------------------------------------------------
        // SUITE 2: The Brain (Llama-3.2-3B) Real Intent & Plan Orchestration
        // -------------------------------------------------------------
        print("[SUITE 2] The Brain (Llama-3.2-3B) Intent & Planning Live Tests")
        
        // Test 2.1: Hinglish Software Automation
        print("  ▶ Testing Hinglish Command: 'Blender mein cube sculpt karo'")
        let t1Start = Date()
        var plan1: OrchestratedPlan? = nil
        do {
            plan1 = try await LLMIntentOrchestrator.shared.plan(transcript: "Blender mein cube sculpt karo")
        } catch {
            print("  ✗ Orchestrator error: \(error)")
        }
        let t1Duration = Int(Date().timeIntervalSince(t1Start) * 1000)
        
        if let p1 = plan1 {
            assertTest(p1.intent == "software_automation", "Plan 1 identified as software_automation", notes: "Duration: \(t1Duration)ms, Intent: '\(p1.intent)'")
            assertTest(p1.targetApplication.lowercased().contains("blender"), "Plan 1 target application identified as Blender", notes: "Target: '\(p1.targetApplication)'")
            assertTest(!p1.steps.isEmpty, "Plan 1 generated executable multi-step sequence", notes: "\(p1.steps.count) steps generated")
            for step in p1.steps {
                print("     Step \(step.step_number): [\(step.action)] param: '\(step.param)'")
            }
        } else {
            assertTest(false, "Plan 1 failed to execute against local Llama-3.2-3B")
            recordBug(
                title: "Llama-3.2-3B Failed To Return Plan for 'Blender mein cube sculpt karo'",
                severity: "Critical",
                description: "Local model call threw an exception or timed out.",
                reproduction: "Call `LLMIntentOrchestrator.shared.plan(transcript: ...)`",
                fixOrStatus: "Ensure Ollama is running and model format=json is supported."
            )
        }

        // Test 2.2: Hindi Colloquial System Control
        print("  ▶ Testing Colloquial Command: 'Spotify band kar do aur volume kam karo'")
        let t2Start = Date()
        var plan2: OrchestratedPlan? = nil
        do {
            plan2 = try await LLMIntentOrchestrator.shared.plan(transcript: "Spotify band kar do aur volume kam karo")
        } catch {
            print("  ✗ Orchestrator error: \(error)")
        }
        let t2Duration = Int(Date().timeIntervalSince(t2Start) * 1000)
        
        if let p2 = plan2 {
            let validIntent2 = (p2.intent == "system_control" || p2.intent == "software_automation")
            assertTest(validIntent2, "Plan 2 recognized as system_control or software_automation", notes: "Duration: \(t2Duration)ms, Intent: '\(p2.intent)'")
            assertTest(p2.targetApplication.lowercased().contains("spotify") || p2.steps.contains(where: { $0.param.lowercased().contains("spotify") || $0.param.lowercased().contains("volume") }), "Plan 2 mentions Spotify or volume control")
            for step in p2.steps {
                print("     Step \(step.step_number): [\(step.action)] param: '\(step.param)'")
            }
        } else {
            assertTest(false, "Plan 2 failed to execute against local Llama-3.2-3B")
        }

        // Test 2.3: Web Search Intent
        print("  ▶ Testing Web Search Command: 'Safari kholo aur google search karo who is the prime minister of india'")
        let t3Start = Date()
        var plan3: OrchestratedPlan? = nil
        do {
            plan3 = try await LLMIntentOrchestrator.shared.plan(transcript: "Safari kholo aur google search karo who is the prime minister of india")
        } catch {
            print("  ✗ Orchestrator error: \(error)")
        }
        let t3Duration = Int(Date().timeIntervalSince(t3Start) * 1000)
        if let p3 = plan3 {
            let validIntent3 = (p3.intent == "web_search" || p3.intent == "software_automation")
            assertTest(validIntent3, "Plan 3 routed to web_search or automation", notes: "Duration: \(t3Duration)ms, Intent: '\(p3.intent)'")
            for step in p3.steps {
                print("     Step \(step.step_number): [\(step.action)] param: '\(step.param)'")
            }
        } else {
            assertTest(false, "Plan 3 failed to execute against local Llama-3.2-3B")
        }
        print("")

        // -------------------------------------------------------------
        // SUITE 3: The Eyes (LLaVA-7B) Multimodal Set-of-Mark Grounding
        // -------------------------------------------------------------
        print("[SUITE 3] The Eyes (LLaVA-7B) Multimodal Visual Grounding Live Tests")
        
        // Generate a synthetic test bitmap with marked targets [A1] and [B2]
        let width = 400
        let height = 200
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: bitmapInfo) else {
            fatalError("Failed to create test graphics context")
        }
        
        // Background dark
        context.setFillColor(CGColor(gray: 0.1, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        
        // Target Box [A1]: "Save Project" button in Green
        context.setFillColor(CGColor(red: 0.1, green: 0.7, blue: 0.2, alpha: 1.0))
        context.fill(CGRect(x: 40, y: 80, width: 120, height: 40))
        
        // Target Box [B2]: "Discard Changes" button in Red
        context.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1.0))
        context.fill(CGRect(x: 220, y: 80, width: 120, height: 40))
        
        guard let cgImg = context.makeImage() else {
            fatalError("Failed to create CGImage")
        }
        let nsImg = NSImage(cgImage: cgImg, size: NSSize(width: width, height: height))
        
        // Convert to base64
        guard let tiffData = nsImg.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiffData),
              let pngData = rep.representation(using: .png, properties: [:]) else {
            fatalError("Failed to convert image to PNG")
        }
        let base64Image = pngData.base64EncodedString()
        
        print("  ▶ Sending tagged frame with marks [A1] (Green Save) and [B2] (Red Discard) to LLaVA-7B...")
        let vlmStart = Date()
        
        let prompt = """
        You are a visual grounding engine for desktop UI automation.
        Inspect the provided screen. Target element: "Save Project button".
        Marks detected: [A1] is the green Save button on the left, [B2] is the red Discard button on the right.
        Output ONLY the alphanumeric tag of the target element. Format: [A1] or [B2].
        """
        
        let requestBody: [String: Any] = [
            "model": "llava:7b",
            "prompt": prompt,
            "images": [base64Image],
            "stream": false,
            "options": [
                "temperature": 0.1,
                "num_predict": 30
            ]
        ]
        
        var vlmSuccess = false
        var vlmResponseText = ""
        var vlmLatencyMs = 0
        
        do {
            let endpoint = URL(string: "http://localhost:11434/api/generate")!
            var req = URLRequest(url: endpoint)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            req.timeoutInterval = 120.0
            
            let (data, resp) = try await URLSession.shared.data(for: req)
            vlmLatencyMs = Int(Date().timeIntervalSince(vlmStart) * 1000)
            
            if let httpResp = resp as? HTTPURLResponse, (200...299).contains(httpResp.statusCode),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let response = json["response"] as? String {
                vlmResponseText = response.trimmingCharacters(in: .whitespacesAndNewlines)
                vlmSuccess = true
            }
        } catch {
            print("  ✗ VLM Call Error: \(error.localizedDescription)")
        }
        
        assertTest(vlmSuccess, "LLaVA-7B processed visual grounding frame", notes: "Latency: \(vlmLatencyMs)ms")
        print("     LLaVA-7B Output: \"\(vlmResponseText)\"")
        
        let foundTag = vlmResponseText.contains("A1") || vlmResponseText.contains("[A1]")
        assertTest(foundTag, "LLaVA-7B accurately identified target tag [A1] (Save button)", notes: "Found in output: '\(vlmResponseText)'")
        
        if !foundTag && vlmSuccess {
            recordBug(
                title: "LLaVA-7B Did Not Output Explicit [A1] Marker",
                severity: "Medium",
                description: "LLaVA-7B responded with text: '\(vlmResponseText)' instead of strict [A1].",
                reproduction: "Run visual grounding prompt on two-button image.",
                fixOrStatus: "Apply regex tag extraction or add few-shot JSON example in VLM prompt."
            )
        }
        
        if vlmLatencyMs > 10000 {
            recordBug(
                title: "LLaVA-7B Cold-Start Latency Exceeds 10 Seconds (\(vlmLatencyMs)ms)",
                severity: "Low",
                description: "On Apple Silicon, initial cold-start loading of 7B VLM weights took \(Double(vlmLatencyMs)/1000.0) seconds.",
                reproduction: "Trigger first visual locate and click on a non-warmed frame.",
                fixOrStatus: "SemanticActionCache successfully bypasses this for cached buttons (<5ms). Maintain Hybrid Mode recommendation for <16GB RAM devices."
            )
        }
        print("")

        // -------------------------------------------------------------
        // SUITE 4: Semantic Action Cache (<5ms Fast Path)
        // -------------------------------------------------------------
        print("[SUITE 4] Semantic Action Cache Performance (<5ms Bypass)")
        let cache = SemanticActionCache.shared
        
        // Test pre-seeded Blender anchor
        let blenderPoint = cache.lookup(targetDescription: "Sculpt Mode dropdown menu", targetApp: "Blender")
        assertTest(blenderPoint != nil, "Pre-seeded Blender Sculpt Mode coordinate resolved instantly", notes: "Coord: \(String(describing: blenderPoint))")
        
        // Measure lookup speed
        let cacheStart = DispatchTime.now()
        _ = cache.lookup(targetDescription: "Sculpt Mode dropdown menu", targetApp: "Blender")
        let cacheEnd = DispatchTime.now()
        let elapsedNanos = cacheEnd.uptimeNanoseconds - cacheStart.uptimeNanoseconds
        let elapsedMicros = Double(elapsedNanos) / 1000.0
        assertTest(elapsedMicros < 5000.0, "Cache lookup completed in <5ms", notes: "\(String(format: "%.2f", elapsedMicros)) µs (\(String(format: "%.3f", elapsedMicros / 1000.0)) ms)")
        
        // Record and hit test
        cache.store(targetDescription: "Google Search Input Field", targetApp: "Safari", coordinate: CGPoint(x: 450, y: 380))
        let hit = cache.lookup(targetDescription: "Google Search Input Field", targetApp: "Safari")
        assertTest(hit == CGPoint(x: 450, y: 380), "Recorded dynamic button coordinate retrieved accurately from cache")
        print("")

        // -------------------------------------------------------------
        // SUITE 5: Dynamic RAM Swapping & Model Suspension
        // -------------------------------------------------------------
        print("[SUITE 5] Dynamic RAM Swapping & Model Suspension")
        let lifecycle = ModelLifecycleManager.shared
        let initialState = await lifecycle.currentVisionState
        print("  ℹ Initial Vision State: \(initialState.rawValue)")
        
        // Acquire vision lease
        let leaseAcquired = await lifecycle.acquireVisionLease()
        let activeState = await lifecycle.currentVisionState
        assertTest(leaseAcquired && activeState == .active, "Vision lease acquired, state transitioned to .active")
        
        // Release vision lease
        await lifecycle.releaseVisionLease()
        let releasedState = await lifecycle.currentVisionState
        assertTest(releasedState == .suspended, "Vision lease released, model offloaded with keep_alive: 0 to free unified memory")
        print("")

        // -------------------------------------------------------------
        // SUITE 6: The Voice (Kokoro-82M & Neural Speech Synthesis)
        // -------------------------------------------------------------
        print("[SUITE 6] The Voice (Kokoro-82M & Neural Speech Pipeline)")
        let voiceEngine = SpeechPipelineEngine.shared
        
        let ttsStartTime = Date()
        voiceEngine.speakResponse("Voice.AI offline speech pipeline verified.")
        let ttsInitMs = Int(Date().timeIntervalSince(ttsStartTime) * 1000)
        assertTest(ttsInitMs < 100, "Speech synthesis dispatch initiated in <100ms", notes: "\(ttsInitMs)ms")
        print("")

        // -------------------------------------------------------------
        // SUITE 7: Calibrated Click Engine & OS Menu Animation Settle
        // -------------------------------------------------------------
        print("[SUITE 7] Calibrated Click Engine & 180ms Settle Verification")
        let settleDelay = CalibratedClickEngine.defaultSettleSleepMs
        assertTest(settleDelay >= 150 && settleDelay <= 250, "Enforces host OS menu animation curve settle delay (150-250ms)", notes: "Configured: \(settleDelay)ms")
        print("")

        // -------------------------------------------------------------
        // Summary & Report Generation
        // -------------------------------------------------------------
        print("=================================================================")
        print("Test Suite Execution Completed!")
        print("Passed: \(passCount) | Failed: \(failCount) | Bugs Identified: \(bugsFound.count)")
        print("=================================================================\n")
    }
}
