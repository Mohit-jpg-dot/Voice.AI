import SwiftUI
import AppKit
import VoiceOSCore

public final class VisualCursorOverlayController: NSObject, ObservableObject, @unchecked Sendable {
    public static let shared = VisualCursorOverlayController()
    
    private var window: NSPanel?
    private var overlayView: NSHostingView<VisualCursorOverlayView>?
    private var autoHideWorkItem: DispatchWorkItem?
    
    @Published public var currentPosition: CGPoint = .zero
    @Published public var isVisible: Bool = false
    @Published public var isClicking: Bool = false
    @Published public var opacity: Double = 0.0
    @Published public var beaconLabel: String = ""
    
    public override init() {
        super.init()
        setupWindow()
        bindEngine()
    }
    
    private func setupWindow() {
        let screenRect = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let panel = NSPanel(
            contentRect: screenRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.ignoresMouseEvents = true // Click-through so user and synthetic events pass through
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        
        let view = VisualCursorOverlayView(controller: self)
        let hosting = NSHostingView(rootView: view)
        panel.contentView = hosting
        
        self.window = panel
        self.overlayView = hosting
    }
    
    private func bindEngine() {
        VisualCursorGuideEngine.shared.onPointerMoved = { [weak self] point, label in
            DispatchQueue.main.async {
                self?.showAt(point: point, label: label)
            }
        }
        VisualCursorGuideEngine.shared.onClickFeedbackTriggered = { [weak self] point in
            DispatchQueue.main.async {
                self?.triggerClickFeedback(at: point)
            }
        }
        VisualCursorGuideEngine.shared.onPointerDismissRequested = { [weak self] in
            DispatchQueue.main.async {
                self?.hide()
            }
        }
        VisualCursorGuideEngine.shared.onTutorialCompleted = { [weak self] in
            DispatchQueue.main.async {
                self?.hide()
            }
        }
    }
    
    public func showAt(point: CGPoint, label: String? = nil, autoHideAfter: TimeInterval = 1.8) {
        autoHideWorkItem?.cancel()
        self.currentPosition = point
        self.beaconLabel = label ?? "Voice.AI Pointing Here"
        self.isVisible = true
        withAnimation(.easeOut(duration: 0.15)) {
            self.opacity = 1.0
            self.isClicking = false
        }
        self.window?.orderFrontRegardless()
        
        // Auto-dismiss safety timer so pointer NEVER stays stuck on screen
        let work = DispatchWorkItem { [weak self] in
            self?.hide()
        }
        self.autoHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + autoHideAfter, execute: work)
    }
    
    public func triggerClickFeedback(at point: CGPoint) {
        autoHideWorkItem?.cancel()
        self.currentPosition = point
        withAnimation(.spring(response: 0.15, dampingFraction: 0.6)) {
            self.isClicking = true
        }
        
        // Ripple click animation, then smoothly vanish
        let work = DispatchWorkItem { [weak self] in
            self?.hide()
        }
        self.autoHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }
    
    public func hide() {
        autoHideWorkItem?.cancel()
        autoHideWorkItem = nil
        withAnimation(.easeOut(duration: 0.25)) {
            self.opacity = 0.0
            self.isClicking = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in
            guard let self = self, self.opacity == 0.0 else { return }
            self.isVisible = false
            self.window?.orderOut(nil)
        }
    }
}

public struct VisualCursorOverlayView: View {
    @ObservedObject var controller: VisualCursorOverlayController
    @State private var pulseScale: CGFloat = 1.0
    @State private var beaconGlow: Double = 0.8
    
    public init(controller: VisualCursorOverlayController) {
        self.controller = controller
    }
    
    public var body: some View {
        GeometryReader { _ in
            if controller.isVisible {
                ZStack {
                    // Pulsing Beacon Target Circle
                    Circle()
                        .stroke(Color.cyan.opacity(0.85), lineWidth: controller.isClicking ? 3 : 2)
                        .frame(width: 44, height: 44)
                        .scaleEffect(controller.isClicking ? 0.7 : pulseScale)
                        .opacity(controller.isClicking ? 1.0 : (2.0 - Double(pulseScale)))
                    
                    Circle()
                        .fill(RadialGradient(
                            colors: controller.isClicking ? [Color.white, Color.cyan] : [Color.cyan.opacity(0.6), Color.blue.opacity(0.1)],
                            center: .center,
                            startRadius: 2,
                            endRadius: 20
                        ))
                        .frame(width: controller.isClicking ? 36 : 28, height: controller.isClicking ? 36 : 28)
                    
                    // Click Ripple Flash
                    if controller.isClicking {
                        Circle()
                            .stroke(Color.white.opacity(0.9), lineWidth: 2.5)
                            .frame(width: 64, height: 64)
                            .scaleEffect(1.3)
                    }
                    
                    // Arrow Beacon pointing towards the target
                    Image(systemName: "arrow.up.left")
                        .font(.system(size: 20, weight: .black))
                        .foregroundColor(controller.isClicking ? Color.cyan : .white)
                        .shadow(color: .black.opacity(0.8), radius: 4, x: 1, y: 1)
                        .offset(x: controller.isClicking ? 12 : 18, y: controller.isClicking ? 12 : 18)
                    
                    // Tooltip Badge
                    if !controller.beaconLabel.isEmpty {
                        Text(controller.beaconLabel)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.88))
                                    .overlay(Capsule().stroke(Color.cyan.opacity(0.7), lineWidth: 1))
                            )
                            .offset(x: 40, y: 32)
                    }
                }
                .position(x: controller.currentPosition.x, y: controller.currentPosition.y)
                .opacity(controller.opacity)
                .onAppear {
                    withAnimation(Animation.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                        pulseScale = 1.6
                        beaconGlow = 1.0
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}
