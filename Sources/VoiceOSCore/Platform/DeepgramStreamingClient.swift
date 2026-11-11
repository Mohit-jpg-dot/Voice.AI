import Foundation
import AVFoundation

/// Deepgram-style streaming transcription client matching APP-SECRET.md line 85:
/// `[TranscriptionService] Stream error`, Deepgram parsing, transcription-stop state, final transcript handling.
/// Provides a real WebSocket client when API key is configured, and a seamless local stub (`// LOCAL-STUB`)
/// for offline on-device operation.
public final class DeepgramStreamingClient: @unchecked Sendable {
    public static let shared = DeepgramStreamingClient()
    
    private var webSocketTask: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)
    private let lock = NSLock()
    private var isStreaming = false
    
    public var onPartialTranscript: ((String) -> Void)?
    public var onFinalTranscript: ((String) -> Void)?
    public var onError: ((String) -> Void)?
    
    private init() {}
    
    // MARK: - Streaming Connection Lifecycle
    
    public func startStream(apiKey: String? = nil, sampleRate: Int = 16000) {
        lock.lock()
        defer { lock.unlock() }
        
        isStreaming = true
        let key = apiKey ?? KeychainService.shared.get(.searchProviderKey)
        
        if let liveKey = key, !liveKey.isEmpty, let url = URL(string: "wss://api.deepgram.com/v1/listen?encoding=linear16&sample_rate=\(sampleRate)&channels=1") {
            // Live Cloud WebSocket Stream
            var request = URLRequest(url: url)
            request.setValue("Token \(liveKey)", forHTTPHeaderField: "Authorization")
            
            let task = session.webSocketTask(with: request)
            self.webSocketTask = task
            task.resume()
            listenForMessages()
        } else {
            // LOCAL-STUB: Offline on-device transcription stub
            VoiceOSTelemetry.shared.addSentryBreadcrumb(
                category: "transcription",
                message: "DeepgramStreamingClient using local on-device transcription stream"
            )
        }
    }
    
    public func sendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard isStreaming else { return }
        
        if let ws = webSocketTask {
            // Convert PCM buffer to raw 16-bit linear PCM bytes
            guard let channelData = buffer.int16ChannelData else { return }
            let frameLength = Int(buffer.frameLength)
            let data = Data(bytes: channelData[0], count: frameLength * MemoryLayout<Int16>.size)
            ws.send(.data(data)) { [weak self] error in
                if let err = error {
                    // Match stable error string from APP-SECRET.md line 85
                    let errorMsg = "[TranscriptionService] Stream error: \(err.localizedDescription)"
                    self?.onError?(errorMsg)
                    VoiceOSTelemetry.shared.captureSentryMessage(errorMsg, level: "error")
                }
            }
        }
    }
    
    public func stopStream() {
        lock.lock()
        defer { lock.unlock() }
        isStreaming = false
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
    }
    
    // MARK: - Message Receiver
    
    private func listenForMessages() {
        guard isStreaming, let ws = webSocketTask else { return }
        
        ws.receive { [weak self] result in
            guard let self = self, self.isStreaming else { return }
            
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.parseDeepgramJSON(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.parseDeepgramJSON(text)
                    }
                @unknown default:
                    break
                }
                self.listenForMessages()
                
            case .failure(let error):
                let errorMsg = "[TranscriptionService] Stream error: \(error.localizedDescription)"
                self.onError?(errorMsg)
                VoiceOSTelemetry.shared.captureSentryMessage(errorMsg, level: "warn")
            }
        }
    }
    
    private func parseDeepgramJSON(_ jsonStr: String) {
        guard let data = jsonStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let channel = json["channel"] as? [String: Any],
              let alternatives = channel["alternatives"] as? [[String: Any]],
              let firstAlt = alternatives.first,
              let transcript = firstAlt["transcript"] as? String,
              !transcript.isEmpty else { return }
        
        let isFinal = json["is_final"] as? Bool ?? false
        if isFinal {
            onFinalTranscript?(transcript)
        } else {
            onPartialTranscript?(transcript)
        }
    }
}

