import SwiftUI
import AppKit
import VoiceOSCore

/// Visual Beacon Screen Tutor Overlay Controller
/// Manages a system-wide non-activating transparent window panel at .floating level.
/// Renders smooth animated pulsing circles directly above target UI coordinates without stealing clicks.
public final class ScreenBeaconTutorOverlayController: NSObject, ObservableObject, @unchecked Sendable {
    public static let shared = ScreenBeaconTutorOverlayController()
    
    private var panel: NSPanel?
    private var hostingView: NSHostingView<ScreenBeaconTutorView>?
    private var autoDismissItem: DispatchWorkItem?
    
    @Published public var targetPoint: CGPoint = .zero
    @Published public var instructionText: String = ""
    @Published public var isVisible: Bool = false
    
    public override init() {
        super.init()
        setupTransparentPanel()
    }
    
    private func setupTransparentPanel() {
        let screenRect = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let overlayPanel = NSPanel(
            contentRect: screenRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        overlayPanel.isOpaque = false
        overlayPanel.backgroundColor = .clear
        overlayPanel.level = .floating
        overlayPanel.ignoresMouseEvents = true // Zero click interception
        overlayPanel.hasShadow = false
        overlayPanel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        
        let view = ScreenBeaconTutorView(controller: self)
        let hosting = NSHostingView(rootView: view)
        overlayPanel.contentView = hosting
        
        self.panel = overlayPanel
        self.hostingView = hosting
    }
    
    public func guideUser(to point: CGPoint, label: String, duration: TimeInterval = 6.0) {
        autoDismissItem?.cancel()
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.targetPoint = point
            self.instructionText = label
            self.isVisible = true
            self.panel?.orderFrontRegardless()
            
            let item = DispatchWorkItem { [weak self] in
                withAnimation(.easeOut(duration: 0.3)) {
                    self?.isVisible = false
                }
            }
            self.autoDismissItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
        }
    }
    
    public func dismiss() {
        autoDismissItem?.cancel()
        DispatchQueue.main.async { [weak self] in
            withAnimation(.easeOut(duration: 0.2)) {
                self?.isVisible = false
            }
        }
    }
}

public struct ScreenBeaconTutorView: View {
    @ObservedObject var controller: ScreenBeaconTutorOverlayController
    @State private var rippleScale: CGFloat = 0.8
    @State private var rippleOpacity: Double = 0.9
    
    public init(controller: ScreenBeaconTutorOverlayController) {
        self.controller = controller
    }
    
    public var body: some View {
        GeometryReader { _ in
            if controller.isVisible {
                ZStack {
                    // Outer Ripple 1
                    Circle()
                        .stroke(Color.cyan.opacity(rippleOpacity), lineWidth: 2.5)
                        .frame(width: 60 * rippleScale, height: 60 * rippleScale)
                    
                    // Outer Ripple 2
                    Circle()
                        .stroke(Color.blue.opacity(rippleOpacity * 0.7), lineWidth: 1.5)
                        .frame(width: 90 * rippleScale, height: 90 * rippleScale)
                    
                    // Inner Glowing Center Ring
                    Circle()
                        .fill(Color.cyan.opacity(0.25))
                        .frame(width: 32, height: 32)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        .shadow(color: .cyan, radius: 10)
                    
                    // Center Precision Dot
                    Circle()
                        .fill(Color.white)
                        .frame(width: 6, height: 6)
                    
                    // Floating Tooltip Badge above coordinate
                    VStack(spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "hand.point.down.fill")
                                .foregroundColor(.cyan)
                                .font(.system(size: 13))
                            Text(controller.instructionText)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.85))
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.cyan.opacity(0.6), lineWidth: 1.5))
                        .shadow(color: Color.black.opacity(0.5), radius: 8, y: 4)
                        
                        // Downward Pointer Arrow
                        Image(systemName: "triangle.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.cyan)
                            .rotationEffect(.degrees(180))
                    }
                    .offset(y: -52)
                }
                .position(x: controller.targetPoint.x, y: controller.targetPoint.y)
                .transition(.scale.combined(with: .opacity))
                .onAppear {
                    withAnimation(Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                        rippleScale = 2.2
                        rippleOpacity = 0.0
                    }
                }
            }
        }
        .allowsHitTesting(false) // Clicks pass through completely to underlying OS
    }
}

