import AppKit
import AVFoundation
import SwiftUI
import VoiceOSCore

// MARK: - Ambient Startup Synth (In-Memory Polyphonic Chime & Pad)

private final class LaunchAmbientSynth {
    static let shared = LaunchAmbientSynth()
    private var player: AVAudioPlayer?

    func playStartupMusic() {
        guard BoringSoundEngine.shared.isSoundEnabled else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let wavData = Self.synthesizeAmbientChordWAV(durationSeconds: 3.3, sampleRate: 44_100)
            DispatchQueue.main.async {
                guard let player = try? AVAudioPlayer(data: wavData) else { return }
                player.volume = 0.55
                player.prepareToPlay()
                player.play()
                self?.player = player
            }
        }
    }

    func fadeOutAndStop() {
        player?.setVolume(0, fadeDuration: 0.45)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.player?.stop()
            self?.player = nil
        }
    }

    private static func synthesizeAmbientChordWAV(durationSeconds: Double, sampleRate: Int) -> Data {
        let totalSamples = Int(durationSeconds * Double(sampleRate))
        var pcm = [Int16](repeating: 0, count: totalSamples)

        // Warm futuristic Cmaj9 + shimmer fifths
        let notes: [(freq: Double, start: Double, amp: Double)] = [
            (130.81, 0.00, 0.22), // C3 warm bass pad
            (196.00, 0.05, 0.18), // G3
            (261.63, 0.12, 0.18), // C4
            (329.63, 0.28, 0.16), // E4
            (392.00, 0.48, 0.14), // G4
            (493.88, 0.72, 0.12), // B4
            (587.33, 1.00, 0.11), // D5 crystalline shimmer
            (783.99, 1.35, 0.08)  // G5 high harmonic
        ]

        for i in 0..<totalSamples {
            let t = Double(i) / Double(sampleRate)
            var sample = 0.0

            for n in notes where t >= n.start {
                let localT = t - n.start
                let attack = min(1.0, localT / 0.22)
                let release = max(0.0, 1.0 - max(0.0, (t - (durationSeconds - 1.1)) / 1.1))
                let env = attack * release * exp(-localT * 0.45)
                let fundamental = sin(2.0 * .pi * n.freq * t)
                let harmonic = 0.25 * sin(2.0 * .pi * (n.freq * 2.0) * t)
                sample += n.amp * env * (fundamental + harmonic)
            }

            let clamped = max(-0.95, min(0.95, sample))
            pcm[i] = Int16(clamped * Double(Int16.max))
        }

        // Build 16-bit mono WAV header
        let byteRate = sampleRate * 2
        let dataSize = pcm.count * 2
        var data = Data(capacity: 44 + dataSize)
        data.append("RIFF".data(using: .ascii)!)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(36 + dataSize).littleEndian, Array.init))
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian, Array.init)) // PCM
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian, Array.init)) // Mono
        data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: UInt32(byteRate).littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: UInt16(2).littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: UInt16(16).littleEndian, Array.init))
        data.append("data".data(using: .ascii)!)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(dataSize).littleEndian, Array.init))
        pcm.withUnsafeBytes { data.append(contentsOf: $0) }
        return data
    }
}

// MARK: - Full-Screen Launch Orb -> Apple Notch Transition View

private struct LaunchOrbSplashView: View {
    let screenHeight: CGFloat
    let onComplete: () -> Void

    @State private var backdropOpacity: Double = 0
    @State private var titleOpacity: Double = 0
    @State private var orbOpacity: Double = 0
    @State private var orbScale: CGFloat = 0.72
    @State private var orbOffsetY: CGFloat = 0
    @State private var stage2Opacity: Double = 0
    @State private var stage2Scale: CGFloat = 0.94
    @State private var finished = false

    var body: some View {
        ZStack {
            Color.black.opacity(backdropOpacity)
                .ignoresSafeArea()

            // Stage 1: "THE WORLD'S FIRST / voice operating system" + Glowing Liquid Orb
            VStack(spacing: 22) {
                VStack(spacing: 8) {
                    Text("THE WORLD'S FIRST")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .tracking(3.4)
                        .foregroundColor(.white.opacity(0.75))

                    Text("voice operating system")
                        .font(.system(size: 38, weight: .semibold, design: .rounded))
                        .tracking(-0.8)
                        .foregroundColor(.white)
                }
                .opacity(titleOpacity)

                // Luminous Blue & White Liquid Wave Orb
                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    Canvas { ctx, size in
                        let rect = CGRect(origin: .zero, size: size)
                        let center = CGPoint(x: rect.midX, y: rect.midY)
                        let radius = min(size.width, size.height) * 0.42

                        // Outer soft blue bloom
                        let outerGlow = Gradient(colors: [
                            Color(red: 0.16, green: 0.56, blue: 1.0).opacity(0.55),
                            Color(red: 0.05, green: 0.30, blue: 1.0).opacity(0.18),
                            Color.clear
                        ])
                        ctx.fill(
                            Path(ellipseIn: rect),
                            with: .radialGradient(outerGlow, center: center, startRadius: radius * 0.7, endRadius: radius * 1.25)
                        )

                        // Clip to main orb circle
                        let orbRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                        ctx.drawLayer { layer in
                            layer.clip(to: Path(ellipseIn: orbRect))

                            // Cobalt-blue upper sphere gradient
                            layer.fill(
                                Path(orbRect),
                                with: .linearGradient(
                                    Gradient(colors: [
                                        Color(red: 0.04, green: 0.24, blue: 0.88),
                                        Color(red: 0.08, green: 0.45, blue: 1.0),
                                        Color(red: 0.35, green: 0.72, blue: 1.0)
                                    ]),
                                    startPoint: CGPoint(x: orbRect.midX, y: orbRect.minY),
                                    endPoint: CGPoint(x: orbRect.midX, y: orbRect.maxY)
                                )
                            )

                            // Animated luminous white liquid wave filling bottom half
                            var wave = Path()
                            let baseLine = orbRect.midY + radius * 0.06
                            wave.move(to: CGPoint(x: orbRect.minX, y: orbRect.maxY))
                            wave.addLine(to: CGPoint(x: orbRect.minX, y: baseLine))
                            let steps = 48
                            for step in 0...steps {
                                let progress = Double(step) / Double(steps)
                                let x = orbRect.minX + progress * orbRect.width
                                let y = baseLine
                                    + sin(progress * .pi * 2.1 + t * 3.1) * (radius * 0.11)
                                    + cos(progress * .pi * 3.4 - t * 2.2) * (radius * 0.05)
                                wave.addLine(to: CGPoint(x: x, y: y))
                            }
                            wave.addLine(to: CGPoint(x: orbRect.maxX, y: orbRect.maxY))
                            wave.closeSubpath()

                            layer.fill(
                                wave,
                                with: .linearGradient(
                                    Gradient(colors: [
                                        Color.white.opacity(0.95),
                                        Color.white,
                                        Color(red: 0.86, green: 0.94, blue: 1.0)
                                    ]),
                                    startPoint: CGPoint(x: orbRect.midX, y: baseLine - radius * 0.15),
                                    endPoint: CGPoint(x: orbRect.midX, y: orbRect.maxY)
                                )
                            )
                        }

                        // Crisp inner rim highlight
                        ctx.stroke(
                            Path(ellipseIn: orbRect),
                            with: .color(Color.white.opacity(0.45)),
                            lineWidth: 1.5
                        )
                    }
                }
                .frame(width: 230, height: 230)
                .scaleEffect(orbScale)
                .opacity(orbOpacity)
                .offset(y: orbOffsetY)
            }

            // Stage 2: Stylized "▼ voice.ai" geometric wordmark + Frosted Glass "Get Started" pill (matching reference Image 2)
            VStack(spacing: 32) {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: 44, weight: .black))
                        .foregroundColor(.white)
                        .offset(y: 2)

                    Text("voice.ai")
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .tracking(-2.0)
                        .foregroundColor(.white)
                }
                .shadow(color: Color.white.opacity(0.30), radius: 24)

                Button(action: { triggerFinish() }) {
                    Text("Get Started")
                        .font(.system(size: 14.5, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 13)
                        .background(.ultraThinMaterial.opacity(0.80))
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.60), Color.white.opacity(0.18)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: Color.black.opacity(0.30), radius: 18, y: 6)
                }
                .buttonStyle(.plain)
            }
            .scaleEffect(stage2Scale)
            .opacity(stage2Opacity)
        }
        .onAppear {
            runChoreography()
        }
    }

    private func runChoreography() {
        LaunchAmbientSynth.shared.playStartupMusic()

        // 1. Stage 1: Fade in backdrop, "THE WORLD'S FIRST / voice operating system" & glowing orb
        withAnimation(.easeOut(duration: 0.60)) {
            backdropOpacity = 0.50
            titleOpacity = 1.0
            orbOpacity = 1.0
            orbScale = 1.0
        }

        // 2. Orb floats and stays visible with ambient audio, then glides upward into the Apple Notch
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.50) {
            withAnimation(.easeOut(duration: 0.40)) {
                titleOpacity = 0.0
            }
            withAnimation(.timingCurve(0.22, 0.9, 0.25, 1.0, duration: 0.85)) {
                orbOffsetY = -(screenHeight * 0.48)
                orbScale = 0.07
                orbOpacity = 0.0
            }
        }

        // 3. Distinct delay between the two screens (~1.2s delay after notch transition), then smoothly reveal Stage 2
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.50) {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.82)) {
                stage2Opacity = 1.0
                stage2Scale = 1.0
            }
        }
    }

    private func triggerFinish() {
        guard !finished else { return }
        finished = true
        LaunchAmbientSynth.shared.fadeOutAndStop()
        withAnimation(.easeOut(duration: 0.3)) {
            stage2Opacity = 0.0
            backdropOpacity = 0.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            onComplete()
        }
    }
}

// MARK: - Window Controller

public final class LaunchOrbSplashController {
    public static let shared = LaunchOrbSplashController()
    private var splashWindow: NSWindow?

    public func presentAndTransition(onComplete: @escaping @Sendable () -> Void) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            onComplete()
            return
        }

        let win = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.level = .screenSaver
        win.backgroundColor = .clear
        win.isOpaque = false
        win.hasShadow = false
        win.ignoresMouseEvents = false
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = LaunchOrbSplashView(screenHeight: screen.frame.height) { [weak self] in
            DispatchQueue.main.async {
                self?.splashWindow?.orderOut(nil)
                self?.splashWindow = nil
                onComplete()
            }
        }

        win.contentView = NSHostingView(rootView: view)
        win.makeKeyAndOrderFront(nil)
        self.splashWindow = win
    }
}

