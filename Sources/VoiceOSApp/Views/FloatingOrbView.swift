import SwiftUI
import VoiceOSCore

/// The Floating Orb widget ("the second pic thing"):
/// A floating circular button with 5 vertical waveform bars.
/// Clicking it opens the main Voice.AI application panel!
public struct FloatingOrbView: View {
    @ObservedObject var appState: AppState
    var onTogglePanel: () -> Void
    var onDragChanged: ((CGSize) -> Void)?
    var onDragEnded: ((CGSize) -> Void)?
    
    @State private var isHovered: Bool = false
    @State private var isPressed: Bool = false
    
    // Waveform bar base heights: [8, 14, 20, 15, 8]
    private let barBaseHeights: [CGFloat] = [8, 14, 20, 15, 8]
    
    public init(
        appState: AppState,
        onTogglePanel: @escaping () -> Void,
        onDragChanged: ((CGSize) -> Void)? = nil,
        onDragEnded: ((CGSize) -> Void)? = nil
    ) {
        self.appState = appState
        self.onTogglePanel = onTogglePanel
        self.onDragChanged = onDragChanged
        self.onDragEnded = onDragEnded
    }
    
    public var body: some View {
        Button(action: {
            // Master requirement: Clicking the orb opens/toggles the main app panel!
            onTogglePanel()
        }) {
            ZStack {
                // Circular White Pill Background matching reference image
                Circle()
                    .fill(Color.white)
                    .frame(width: 46, height: 46)
                    .shadow(color: Color.black.opacity(isHovered ? 0.25 : 0.16), radius: isHovered ? 8 : 5, x: 0, y: isHovered ? 4 : 2)
                    .overlay(
                        Circle()
                            .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
                    )
                
                // 5 Vertical Audio Waveform Bars (Black)
                HStack(alignment: .center, spacing: 2.8) {
                    ForEach(0..<5, id: \.self) { index in
                        let levelMultiplier: CGFloat = {
                            if case .listening = appState.executionState {
                                let live = (index < appState.audioLevels.count) ? appState.audioLevels[index] : 0.5
                                return max(0.4, live * 1.8)
                            } else {
                                return 1.0
                            }
                        }()
                        
                        let barHeight = max(4.0, barBaseHeights[index] * levelMultiplier)
                        
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.black.opacity(0.88))
                            .frame(width: 2.8, height: min(24, barHeight))
                            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: appState.audioLevels)
                    }
                }
            }
            .scaleEffect(isPressed ? 0.92 : (isHovered ? 1.06 : 1.0))
            .animation(.spring(response: 0.28, dampingFraction: 0.75), value: isHovered)
            .animation(.spring(response: 0.15, dampingFraction: 0.6), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            isHovered = hovering
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 3)
                .onChanged { value in
                    onDragChanged?(value.translation)
                }
                .onEnded { value in
                    onDragEnded?(value.translation)
                }
        )
        .contextMenu {
            Button("Open Voice.AI Panel") {
                onTogglePanel()
            }
            Button(action: {
                if case .listening = appState.executionState {
                    appState.stopVoice()
                } else {
                    appState.triggerVoice(mode: .agent)
                }
            }) {
                Text(appState.isCurrentlyListening ? "Stop Voice" : "Start Voice")
            }
            Divider()
            Button("Hide Floating Orb") {
                appState.isFloatingOrbVisible = false
            }
        }
        .help("Click to open Voice.AI panel")
    }
}
