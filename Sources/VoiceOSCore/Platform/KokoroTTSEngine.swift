import Foundation
import AVFoundation

public struct KokoroDiagnostics: Sendable {
    public let hasWeights: Bool
    public let weightsSizeBytes: Int64
    public let hasVoicePack: Bool
    public let runtimeKind: String?
    public let pythonPath: String?
    public let statusSummary: String
    
    public var isFullyReady: Bool {
        hasWeights && runtimeKind != nil
    }
}

public struct KokoroVoicePreset: Identifiable, Sendable, Equatable {
    public let id: String
    public let label: String
    public let style: String

    public static let presets: [KokoroVoicePreset] = [
        KokoroVoicePreset(id: "af_heart", label: "Heart (Warm US)", style: "Warm"),
        KokoroVoicePreset(id: "bm_george", label: "George (British JARVIS)", style: "British Butler"),
        KokoroVoicePreset(id: "bf_emma", label: "Emma (British FRIDAY)", style: "British Warm"),
        KokoroVoicePreset(id: "am_adam", label: "Adam (Calm Male)", style: "Composed"),
        KokoroVoicePreset(id: "am_michael", label: "Michael (Rich Male)", style: "Deep"),
        KokoroVoicePreset(id: "af_bella", label: "Bella (Expressive)", style: "Expressive"),
        KokoroVoicePreset(id: "af_sarah", label: "Sarah (Clear)", style: "Neutral")
    ]
}

public protocol TTSServiceProtocol: Sendable {
    func speak(text: String, voice: String?, speed: Float, completion: (@Sendable (Bool) -> Void)?)
    func stop()
}

/// On-device Kokoro-82M Neural TTS Engine.
/// Uses ~/.voiceos/models/kokoro.onnx (+ voices/af_heart.bin) via either a local kokoro-tts HTTP server
/// (localhost:8880) or an available Python `kokoro_onnx` runtime, and cleanly reports readiness.
public final class KokoroTTSEngine: NSObject, TTSServiceProtocol, @unchecked Sendable, AVAudioPlayerDelegate {
    public static let shared = KokoroTTSEngine()
    
    public static var modelsDir: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".voiceos/models", isDirectory: true)
    }
    
    public static var weightsURL: URL {
        modelsDir.appendingPathComponent("kokoro.onnx")
    }
    
    public static var voicePackURL: URL {
        let primary = modelsDir.appendingPathComponent("voices-v1.0.bin")
        if FileManager.default.fileExists(atPath: primary.path) {
            return primary
        }
        return modelsDir.appendingPathComponent("voices/af_heart.bin")
    }
    
    private var audioPlayer: AVAudioPlayer?
    private var playbackCompletion: (@Sendable (Bool) -> Void)?
    private let lock = NSLock()
    private let workerLock = NSLock()
    private var workerProcess: Process?
    private var workerStdin: FileHandle?
    private var workerStdout: FileHandle?
    private var cachedPythonWithKokoro: String?
    private var hasProbedPython = false
    private var cachedServerReachable = false
    private var lastServerProbe: Date = .distantPast
    
    public var isPreferredForTTS: Bool {
        get {
            if UserDefaults.standard.object(forKey: "voiceos.tts.prefer_kokoro") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "voiceos.tts.prefer_kokoro")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "voiceos.tts.prefer_kokoro")
        }
    }

    public var selectedVoiceId: String {
        get {
            let saved = UserDefaults.standard.string(forKey: "voiceos.kokoro_voice_id")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return saved.isEmpty ? "af_heart" : saved
        }
        set {
            let clean = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(clean.isEmpty ? "af_heart" : clean, forKey: "voiceos.kokoro_voice_id")
        }
    }
    
    private override init() {
        super.init()
        // Warm up Python / kokoro-tts runtime discovery and persistent ONNX worker off main thread at launch
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            let diag = self.diagnostics(forceRefresh: true)
            if diag.hasWeights, diag.hasVoicePack, let py = diag.pythonPath {
                self.ensurePersistentWorker(pythonPath: py)
            }
        }
    }
    
    public func diagnostics(forceRefresh: Bool = false) -> KokoroDiagnostics {
        let weightsPath = Self.weightsURL.path
        var size: Int64 = 0
        if let attrs = try? FileManager.default.attributesOfItem(atPath: weightsPath),
           let s = attrs[.size] as? Int64 {
            size = s
        }
        let hasWeights = size > 1_000_000
        
        var hasVoicePack = false
        if let vAttrs = try? FileManager.default.attributesOfItem(atPath: Self.voicePackURL.path),
           let vSize = vAttrs[.size] as? Int64 {
            hasVoicePack = vSize > 1_000
        }
        
        let pyPath = findPythonWithKokoroOnnx(forceRefresh: forceRefresh)
        let serverRunning = isLocalKokoroServerReachable()
        
        let runtimeKind: String?
        if serverRunning {
            runtimeKind = "kokoro-tts HTTP (:8880)"
        } else if pyPath != nil {
            runtimeKind = "kokoro-onnx (Python)"
        } else {
            runtimeKind = nil
        }
        
        let summary: String
        if !hasWeights {
            if size > 0 {
                summary = "Corrupted or incomplete weights (\(size) bytes). Re-download Kokoro-82M (86 MB)."
            } else {
                summary = "Kokoro-82M weights not downloaded yet (expected in ~/.voiceos/models/kokoro.onnx)."
            }
        } else if let rt = runtimeKind {
            summary = "Kokoro-82M active via \(rt) (\(size / 1_048_576) MB)."
        } else {
            summary = "Weights ready (\(size / 1_048_576) MB); falling back to macOS Neural TTS because kokoro-onnx/kokoro-tts runtime is not installed."
        }
        
        return KokoroDiagnostics(
            hasWeights: hasWeights,
            weightsSizeBytes: size,
            hasVoicePack: hasVoicePack,
            runtimeKind: runtimeKind,
            pythonPath: pyPath,
            statusSummary: summary
        )
    }
    
    public func stop() {
        lock.lock()
        let player = audioPlayer
        audioPlayer = nil
        let cb = playbackCompletion
        playbackCompletion = nil
        lock.unlock()
        
        player?.stop()
        cb?(false)
    }
    
    public func speak(text: String, voice: String? = nil, speed: Float = 1.0, completion: (@Sendable (Bool) -> Void)? = nil) {
        let resolvedVoice = voice ?? selectedVoiceId
        let weightsPath = Self.weightsURL.path
        let weightsSize = ((try? FileManager.default.attributesOfItem(atPath: weightsPath))?[.size] as? Int64) ?? 0
        guard weightsSize > 1_000_000 else {
            completion?(false)
            return
        }
        
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else {
                completion?(false)
                return
            }
            
            // Probe runtimes off the main thread so first speech never misses due to cold cache
            let diag = self.diagnostics()
            guard diag.isFullyReady else {
                completion?(false)
                return
            }
            
            // 1. Try kokoro-tts local server on port 8880
            if let audioData = await self.synthesizeViaServer(text: text, voice: resolvedVoice, speed: speed) {
                await self.playAudioData(audioData, completion: completion)
                return
            }
            
            // 2. Try Python kokoro_onnx runtime if installed
            if let py = diag.pythonPath,
               let wavData = self.synthesizeViaPython(pythonPath: py, text: text, voice: resolvedVoice, speed: speed) {
                await self.playAudioData(wavData, completion: completion)
                return
            }
            
            completion?(false)
        }
    }
    
    private func playAudioData(_ data: Data, completion: (@Sendable (Bool) -> Void)?) async {
        await MainActor.run {
            do {
                let player = try AVAudioPlayer(data: data)
                player.delegate = self
                player.prepareToPlay()
                self.lock.lock()
                self.audioPlayer = player
                self.playbackCompletion = completion
                self.lock.unlock()
                if !player.play() {
                    self.lock.lock()
                    self.audioPlayer = nil
                    self.playbackCompletion = nil
                    self.lock.unlock()
                    completion?(false)
                }
            } catch {
                completion?(false)
            }
        }
    }
    
    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        lock.lock()
        let cb = playbackCompletion
        playbackCompletion = nil
        audioPlayer = nil
        lock.unlock()
        cb?(flag)
    }
    
    private func isLocalKokoroServerReachable() -> Bool {
        lock.lock()
        let age = Date().timeIntervalSince(lastServerProbe)
        let cached = cachedServerReachable
        lock.unlock()
        if age < 10.0 {
            return cached
        }
        if Thread.isMainThread {
            Task.detached(priority: .utility) { [weak self] in
                _ = self?.probeServerSync()
            }
            return cached
        }
        return probeServerSync()
    }
    
    private func probeServerSync() -> Bool {
        guard let url = URL(string: "http://127.0.0.1:8880/v1/audio/voices") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 0.25
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        let task = URLSession.shared.dataTask(with: req) { _, resp, _ in
            if let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                ok = true
            }
            sem.signal()
        }
        task.resume()
        _ = sem.wait(timeout: .now() + 0.3)
        lock.lock()
        cachedServerReachable = ok
        lastServerProbe = Date()
        lock.unlock()
        return ok
    }
    
    private func synthesizeViaServer(text: String, voice: String, speed: Float) async -> Data? {
        guard let url = URL(string: "http://127.0.0.1:8880/v1/audio/speech") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 8.0
        let body: [String: Any] = [
            "model": "kokoro",
            "input": text,
            "voice": voice,
            "response_format": "wav",
            "speed": speed
        ]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        req.httpBody = httpBody
        
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode), data.count > 100 else {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }
    
    private func ensurePersistentWorker(pythonPath: String) {
        workerLock.lock()
        defer { workerLock.unlock() }
        if let proc = workerProcess, proc.isRunning, workerStdin != nil, workerStdout != nil {
            return
        }
        stopPersistentWorkerLocked()
        
        let weightsPath = Self.weightsURL.path
        let voicesPath = Self.voicePackURL.path
        guard FileManager.default.fileExists(atPath: weightsPath),
              FileManager.default.fileExists(atPath: voicesPath) else { return }
        
        let workerScript = """
        import sys, json
        import soundfile as sf
        from kokoro_onnx import Kokoro

        kokoro = Kokoro(sys.argv[1], sys.argv[2])
        sys.stdout.write("READY\\n")
        sys.stdout.flush()

        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            try:
                req = json.loads(line)
                samples, sr = kokoro.create(
                    req["text"],
                    voice=req.get("voice", "af_heart"),
                    speed=float(req.get("speed", 1.0)),
                    lang="en-us"
                )
                sf.write(req["out"], samples, sr)
                sys.stdout.write("OK\\n")
            except Exception as e:
                sys.stdout.write("ERR\\n")
            sys.stdout.flush()
        """
        
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: pythonPath)
        proc.arguments = ["-u", "-c", workerScript, weightsPath, voicesPath]
        let inPipe = Pipe()
        let outPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = FileHandle.nullDevice
        
        do {
            try proc.run()
            // Wait for READY\n handshake from Python after ONNX load
            if let readyLine = readLineBlocking(from: outPipe.fileHandleForReading), readyLine == "READY" {
                workerProcess = proc
                workerStdin = inPipe.fileHandleForWriting
                workerStdout = outPipe.fileHandleForReading
            } else {
                proc.terminate()
            }
        } catch {}
    }
    
    private func stopPersistentWorkerLocked() {
        try? workerStdin?.close()
        workerProcess?.terminate()
        workerProcess = nil
        workerStdin = nil
        workerStdout = nil
    }
    
    private func readLineBlocking(from handle: FileHandle) -> String? {
        var buffer = Data()
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { return nil }
            for byte in chunk {
                if byte == 0x0A {
                    return String(data: buffer, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                buffer.append(byte)
            }
        }
    }

    private func synthesizeViaPython(pythonPath: String, text: String, voice: String, speed: Float) -> Data? {
        let tmpOut = FileManager.default.temporaryDirectory.appendingPathComponent("voiceai_kokoro_\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: tmpOut) }
        guard FileManager.default.fileExists(atPath: Self.voicePackURL.path) else { return nil }
        
        ensurePersistentWorker(pythonPath: pythonPath)
        
        workerLock.lock()
        defer { workerLock.unlock() }
        
        if let proc = workerProcess, proc.isRunning,
           let stdinHandle = workerStdin,
           let stdoutHandle = workerStdout {
            let payload: [String: Any] = [
                "text": text,
                "voice": voice,
                "speed": speed,
                "out": tmpOut.path
            ]
            if var jsonData = try? JSONSerialization.data(withJSONObject: payload) {
                jsonData.append(0x0A)
                stdinHandle.write(jsonData)
                if let reply = readLineBlocking(from: stdoutHandle), reply == "OK",
                   let wav = try? Data(contentsOf: tmpOut), wav.count > 100 {
                    return wav
                }
                stopPersistentWorkerLocked()
            }
        }
        return nil
    }
    
    private func findPythonWithKokoroOnnx(forceRefresh: Bool) -> String? {
        lock.lock()
        if hasProbedPython && !forceRefresh {
            let cached = cachedPythonWithKokoro
            lock.unlock()
            return cached
        }
        let cached = cachedPythonWithKokoro
        lock.unlock()
        
        if Thread.isMainThread {
            Task.detached(priority: .utility) { [weak self] in
                _ = self?.findPythonWithKokoroOnnx(forceRefresh: forceRefresh)
            }
            return cached
        }
        
        let candidates = candidatePythonExecutables()
        var found: String? = nil
        for py in candidates {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: py)
            proc.arguments = ["-c", "import kokoro_onnx, soundfile"]
            proc.standardOutput = Pipe()
            proc.standardError = Pipe()
            if (try? proc.run()) != nil {
                proc.waitUntilExit()
                if proc.terminationStatus == 0 {
                    found = py
                    break
                }
            }
        }
        
        lock.lock()
        cachedPythonWithKokoro = found
        hasProbedPython = true
        lock.unlock()
        return found
    }
    
    private func candidatePythonExecutables() -> [String] {
        var paths: [String] = [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3"
        ]
        let condaBase = "/opt/homebrew/Caskroom/miniconda/base"
        paths.append("\(condaBase)/bin/python3")
        if let envs = try? FileManager.default.contentsOfDirectory(atPath: "\(condaBase)/envs") {
            for env in envs {
                paths.append("\(condaBase)/envs/\(env)/bin/python")
            }
        }
        return paths.filter { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
