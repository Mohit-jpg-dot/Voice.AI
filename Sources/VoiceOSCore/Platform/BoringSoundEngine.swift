import Foundation
import AVFoundation
import AppKit

/// Pure synthesized sound engine implementing the boringfloor.com / Office Chimes acoustic soundpack.
/// Synthesizes minimalist, non-fatiguing, 16-bit mono 22,050 Hz PCM chimes in memory with zero external asset dependencies.
public final class BoringSoundEngine: @unchecked Sendable {
    public static let shared = BoringSoundEngine()
    
    public enum SoundCue: String, CaseIterable, Sendable {
        /// 40ms, Sine 660 Hz, -12dB: Something joined queue / mic active
        case queued
        /// 60ms, Glide 520->640 Hz, -14dB: Message / prompt sent
        case send
        /// 90ms, Two-tone C5->G5: Assistant begins response
        case reply
        /// 110ms, Rising triad C5-E5-G5: Task or action completed successfully
        case done
        /// 80ms, Low-pass brown-noise pop: Computer control / system dispatch executed
        case dispatch
        /// 140ms, 2x 55ms square 880 Hz beeps: Permission or user attention requested
        case alert
        /// 140ms, Descent 440->220 Hz: Action error or speech unrecognized
        case error
        /// 35ms, Crisp tactile pop: Notch opens from resting bezel
        case notchOpen
        /// 45ms, Soft damping snap: Notch snaps back into bezel
        case notchClose
        /// 25ms, Mechanical micro-click: UI button or switch tapped
        case tap
    }
    
    public var isSoundEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: "VoiceOS_SoundFeedbackEnabled") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "VoiceOS_SoundFeedbackEnabled")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "VoiceOS_SoundFeedbackEnabled")
        }
    }
    
    public var masterVolume: Float = 0.85
    
    private var players: [SoundCue: AVAudioPlayer] = [:]
    private var wavDataMap: [SoundCue: Data] = [:]
    private let sampleRate: Double = 22050.0
    private let lock = NSLock()
    
    public init() {
        synthesizeAllSounds()
    }
    
    // MARK: - Playback Methods
    
    public func play(_ cue: SoundCue) {
        guard isSoundEnabled else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            defer { self.lock.unlock() }
            
            if let player = self.players[cue] {
                player.volume = self.masterVolume
                player.currentTime = 0
                player.play()
            } else if let data = self.wavDataMap[cue] {
                // Fallback NSSound if AVAudioPlayer was uninitialized
                if let sound = NSSound(data: data) {
                    sound.play()
                }
            }
        }
    }
    
    public func playQueued() { play(.queued) }
    public func playSend() { play(.send) }
    public func playReply() { play(.reply) }
    public func playDone() { play(.done) }
    public func playDispatch() { play(.dispatch) }
    public func playAlert() { play(.alert) }
    public func playError() { play(.error) }
    public func playNotchOpen() { play(.notchOpen) }
    public func playNotchClose() { play(.notchClose) }
    public func playTap() { play(.tap) }
    
    // MARK: - Waveform Synthesis
    
    private func synthesizeAllSounds() {
        for cue in SoundCue.allCases {
            let samples = generateSamples(for: cue)
            let wavData = makeWavData(samples: samples, sampleRate: Int(sampleRate))
            wavDataMap[cue] = wavData
            
            if let player = try? AVAudioPlayer(data: wavData) {
                player.prepareToPlay()
                players[cue] = player
            }
        }
    }
    
    private func generateSamples(for cue: SoundCue) -> [Float] {
        let sr = sampleRate
        
        switch cue {
        case .queued:
            // 40ms, Sine 660 Hz, -12dB (gain ~0.25)
            let n = Int(0.040 * sr)
            return (0..<n).map { i in
                let t = Double(i) / sr
                let env = sin(Double.pi * Double(i) / Double(n))
                return Float(0.25 * env * sin(2.0 * Double.pi * 660.0 * t))
            }
            
        case .send:
            // 60ms, Glide 520->640 Hz, -14dB (gain ~0.20)
            let n = Int(0.060 * sr)
            return (0..<n).map { i in
                let t = Double(i) / sr
                let f0 = 520.0
                let f1 = 640.0
                let phase = 2.0 * Double.pi * (f0 * t + 0.5 * (f1 - f0) * (t * t / 0.060))
                let env = sin(Double.pi * Double(i) / Double(n))
                return Float(0.20 * env * sin(phase))
            }
            
        case .reply:
            // 90ms, Two-tone C5 (523.25 Hz) -> G5 (783.99 Hz)
            let n = Int(0.090 * sr)
            let nHalf = n / 2
            return (0..<n).map { i in
                let t = Double(i) / sr
                if i < nHalf {
                    let env = sin(Double.pi * Double(i) / Double(nHalf))
                    return Float(0.22 * env * sin(2.0 * Double.pi * 523.25 * t))
                } else {
                    let env = sin(Double.pi * Double(i - nHalf) / Double(n - nHalf))
                    return Float(0.22 * env * sin(2.0 * Double.pi * 783.99 * t))
                }
            }
            
        case .done:
            // 110ms, Rising triad C5 (523.25 Hz) -> E5 (659.25 Hz) -> G5 (783.99 Hz)
            let n = Int(0.110 * sr)
            let n3 = n / 3
            return (0..<n).map { i in
                let t = Double(i) / sr
                if i < n3 {
                    let env = sin(Double.pi * Double(i) / Double(n3))
                    return Float(0.25 * env * sin(2.0 * Double.pi * 523.25 * t))
                } else if i < 2 * n3 {
                    let env = sin(Double.pi * Double(i - n3) / Double(n3))
                    return Float(0.25 * env * sin(2.0 * Double.pi * 659.25 * t))
                } else {
                    let env = sin(Double.pi * Double(i - 2 * n3) / Double(n - 2 * n3))
                    return Float(0.25 * env * sin(2.0 * Double.pi * 783.99 * t))
                }
            }
            
        case .dispatch:
            // 80ms, Low-pass brown-noise mechanical swoosh
            let n = Int(0.080 * sr)
            var last: Double = 0.0
            return (0..<n).map { i in
                let white = Double.random(in: -1.0...1.0)
                let brown = (last + (0.05 * white)) / 1.05
                last = brown
                let env = sin(Double.pi * Double(i) / Double(n))
                return Float(0.35 * env * brown)
            }
            
        case .alert:
            // 140ms, 2 x 55ms square 880 Hz beeps with 30ms silence
            let nBeep = Int(0.055 * sr)
            let nGap = Int(0.030 * sr)
            var res: [Float] = []
            res.reserveCapacity(2 * nBeep + nGap)
            for i in 0..<nBeep {
                let env = sin(Double.pi * Double(i) / Double(nBeep))
                let sq: Double = sin(2.0 * Double.pi * 880.0 * (Double(i) / sr)) > 0 ? 1.0 : -1.0
                res.append(Float(0.18 * env * sq))
            }
            res.append(contentsOf: [Float](repeating: 0.0, count: nGap))
            for i in 0..<nBeep {
                let env = sin(Double.pi * Double(i) / Double(nBeep))
                let sq: Double = sin(2.0 * Double.pi * 880.0 * (Double(i) / sr)) > 0 ? 1.0 : -1.0
                res.append(Float(0.18 * env * sq))
            }
            return res
            
        case .error:
            // 140ms, Descent 440->220 Hz
            let n = Int(0.140 * sr)
            return (0..<n).map { i in
                let t = Double(i) / sr
                let f0 = 440.0
                let f1 = 220.0
                let phase = 2.0 * Double.pi * (f0 * t + 0.5 * (f1 - f0) * (t * t / 0.140))
                let env = sin(Double.pi * Double(i) / Double(n))
                return Float(0.25 * env * sin(phase))
            }
            
        case .notchOpen:
            // 35ms, Crisp tactile micro-pop (1200 Hz fast exponential decay)
            let n = Int(0.035 * sr)
            return (0..<n).map { i in
                let t = Double(i) / sr
                let env = exp(-Double(i) / (0.008 * sr))
                return Float(0.30 * env * sin(2.0 * Double.pi * 1200.0 * t))
            }
            
        case .notchClose:
            // 45ms, Damping snap (480 Hz acoustic click)
            let n = Int(0.045 * sr)
            return (0..<n).map { i in
                let t = Double(i) / sr
                let env = exp(-Double(i) / (0.012 * sr))
                return Float(0.25 * env * sin(2.0 * Double.pi * 480.0 * t))
            }
            
        case .tap:
            // 25ms, Mechanical key tap (850 Hz micro-click)
            let n = Int(0.025 * sr)
            return (0..<n).map { i in
                let t = Double(i) / sr
                let env = exp(-Double(i) / (0.006 * sr))
                return Float(0.22 * env * sin(2.0 * Double.pi * 850.0 * t))
            }
        }
    }
    
    // MARK: - WAV Header Construction (16-bit Mono PCM)
    
    private func makeWavData(samples: [Float], sampleRate: Int) -> Data {
        let byteCount = samples.count * 2
        var data = Data()
        data.reserveCapacity(44 + byteCount)
        
        // RIFF chunk
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        var chunkSize = UInt32(36 + byteCount).littleEndian
        data.append(Data(bytes: &chunkSize, count: 4))
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
        
        // fmt chunk
        data.append(contentsOf: [0x66, 0x6d, 0x74, 0x20]) // "fmt "
        var subchunk1Size = UInt32(16).littleEndian
        data.append(Data(bytes: &subchunk1Size, count: 4))
        var audioFormat = UInt16(1).littleEndian // PCM
        data.append(Data(bytes: &audioFormat, count: 2))
        var numChannels = UInt16(1).littleEndian // Mono
        data.append(Data(bytes: &numChannels, count: 2))
        var sRate = UInt32(sampleRate).littleEndian
        data.append(Data(bytes: &sRate, count: 4))
        var byteRate = UInt32(sampleRate * 2).littleEndian
        data.append(Data(bytes: &byteRate, count: 4))
        var blockAlign = UInt16(2).littleEndian
        data.append(Data(bytes: &blockAlign, count: 2))
        var bitsPerSample = UInt16(16).littleEndian
        data.append(Data(bytes: &bitsPerSample, count: 2))
        
        // data chunk
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        var subchunk2Size = UInt32(byteCount).littleEndian
        data.append(Data(bytes: &subchunk2Size, count: 4))
        
        // PCM 16-bit samples
        for s in samples {
            let clamped = max(-1.0, min(1.0, Double(s)))
            var intVal = Int16(clamped * 32767.0).littleEndian
            data.append(Data(bytes: &intVal, count: 2))
        }
        
        return data
    }
}

