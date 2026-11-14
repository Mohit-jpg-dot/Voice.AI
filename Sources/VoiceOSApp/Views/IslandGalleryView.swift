// Ported from islandcn, MIT License, Copyright (c) 2026 Leo. Modified for Swift.
// Debug gallery window for interactive testing of all islandcn engine presentations and presets.

import SwiftUI
import AppKit
import VoiceOSCore

public struct IslandGalleryView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var activityCenter: ActivityCenter = ActivityCenter.shared

    @State private var reduceMotionEnabled: Bool = false
    @State private var noNotchSimulation: Bool = false
    @State private var sensitivePreviews: Bool = false
    @State private var statusMessage: String = "Ready. Select a preset or presentation below to test."

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "sparkles.rectangle.stack.fill")
                            .font(.system(size: 20))
                            .foregroundColor(DesignTokens.Colors.accentCyan)
                        Text("Dynamic Island Gallery")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                    }
                    Text("Interactive test harness for islandcn engine presentations, presets, and safety lanes.")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
                .padding(.bottom, 6)

                // Status Banner
                HStack {
                    Circle()
                        .fill(activityCenter.currentScene.presentation == .idle ? Color.gray : Color.green)
                        .frame(width: 8, height: 8)
                    Text("Current Presentation: \(activityCenter.currentScene.contentKey)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                    Spacer()
                    Text("Active: \(activityCenter.activities.count)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.gray)
                }
                .padding(10)
                .background(Color.white.opacity(0.06))
                .cornerRadius(8)

                // Environment Toggles
                VStack(alignment: .leading, spacing: 10) {
                    Text("Environment Controls")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(DesignTokens.Colors.accentCyan)

                    HStack(spacing: 20) {
                        Toggle("Reduce Motion", isOn: $reduceMotionEnabled)
                            .toggleStyle(.switch)
                            .onChange(of: reduceMotionEnabled) { _, val in
                                statusMessage = val ? "Reduce Motion enabled (0.2s linear crossfades)." : "Dynamic spring physics active."
                            }

                        Toggle("Simulate No Notch", isOn: $noNotchSimulation)
                            .toggleStyle(.switch)

                        Toggle("Show Message Previews", isOn: $sensitivePreviews)
                            .toggleStyle(.switch)
                            .onChange(of: sensitivePreviews) { _, val in
                                activityCenter.showSensitivePreviewsInNotch = val
                            }
                    }
                }
                .padding(12)
                .background(Color.black.opacity(0.3))
                .cornerRadius(10)

                // Presets Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Presets (Voice.AI Native)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(DesignTokens.Colors.accentCyan)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        Button("Timer (10 min)") {
                            TimerActivityManager.shared.createTimer(durationSeconds: 600, label: "Tea Timer")
                            statusMessage = "Started 10 min Tea Timer."
                        }

                        Button("Now Playing (Spotify)") {
                            let media = NowPlayingItem(
                                title: "Nicole Kidman",
                                artistOrChannel: "ADÉLA",
                                albumOrContext: "PRIMA",
                                source: .spotify,
                                isPlaying: true,
                                progress: 0.1,
                                positionSeconds: 13,
                                durationSeconds: 181,
                                artworkUrl: ""
                            )
                            appState.currentMedia = media
                            NowPlayingMediaManager.shared.onMediaChanged?(media)
                            statusMessage = "Now playing Spotify started."
                        }

                        Button("Mic Recording") {
                            RecordingActivityBridge.shared.startRecording(sourceName: "Voice Dictation")
                            statusMessage = "Recording indicator started (cannot be hidden while active)."
                        }

                        Button("Upload Progress (45%)") {
                            let id = UploadProgressActivityManager.shared.startProgress(id: "upload_demo", title: "Monthly Report.pdf")
                            UploadProgressActivityManager.shared.updateProgress(id: id, progress: 0.45, subtitle: "Uploading 4.5 of 10 MB")
                            statusMessage = "Upload progress at 45%."
                        }

                        Button("Nearby Shelf (+3)") {
                            ShelfNearbyActivityBridge.shared.notifyItemsAdded(count: 3)
                            statusMessage = "Added 3 items to shelf."
                        }

                        Button("AirDrop Share") {
                            ShelfNearbyActivityBridge.shared.notifyAirDropShareOpened(itemCount: 2)
                            statusMessage = "AirDrop share sheet opened."
                        }

                        Button("Battery (Charging)") {
                            BatteryActivityMonitor.shared.triggerManualBatteryDisplay()
                            statusMessage = "Battery charging status triggered."
                        }

                        Button("Incoming Chat Reply") {
                            CommunicationActivityBridge.shared.presentIncomingMessage(IncomingMessageAlert(
                                senderName: "Sarah Chen",
                                channelName: "Design",
                                previewSnippet: "The new notch layout looks fantastic!"
                            ))
                            statusMessage = "Incoming message alert presented."
                        }

                        Button("Computer Use ETA") {
                            StepProgressActivityManager.shared.startTask(totalSteps: 15, budgetSeconds: 85, initialDescription: "Opening Settings window...")
                            statusMessage = "Computer use step progress active."
                        }
                    }
                }
                .padding(12)
                .background(Color.black.opacity(0.3))
                .cornerRadius(10)

                // Presentation Controls
                VStack(alignment: .leading, spacing: 12) {
                    Text("Presentation Modes & Edge Cases")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(DesignTokens.Colors.accentCyan)

                    HStack(spacing: 10) {
                        Button("Trigger Split (Timer + Music)") {
                            TimerActivityManager.shared.createTimer(durationSeconds: 300, label: "Quick Timer")
                            let media = NowPlayingItem(
                                title: "Midnight City",
                                artistOrChannel: "M83",
                                albumOrContext: "Hurry Up",
                                source: .spotify,
                                isPlaying: true,
                                progress: 0.2,
                                positionSeconds: 45,
                                durationSeconds: 240,
                                artworkUrl: ""
                            )
                            appState.currentMedia = media
                            NowPlayingMediaManager.shared.onMediaChanged?(media)
                            statusMessage = "Split view activated (Two concurrent activities)."
                        }

                        Button("Long Text Overflow") {
                            let content = ActivityContent(
                                compact: ActivityCompactSlots(leading: .text("Alert"), trailing: .text("99+")),
                                minimal: .symbol(name: "bubble.left.fill"),
                                expanded: ActivityExpandedSlots(
                                    leading: .symbol(name: "text.bubble.fill", tint: "blue"),
                                    trailing: .text("Now"),
                                    center: .text("Very Long Summary Title That Definitely Wraps Multiple Lines Across The Notch"),
                                    bottom: .text("This detailed message contains extended body text to verify that the adaptive notch expands comfortably without truncating and enables smooth vertical scrolling.")
                                )
                            )
                            activityCenter.start(ActivityOptions(
                                id: "long-text-demo",
                                label: "Long Text",
                                priority: ActivityPriority.alert,
                                alert: true,
                                content: content
                            ))
                            statusMessage = "Long text card expanded."
                        }

                        Button("Stack 4 Activities") {
                            TimerActivityManager.shared.createTimer(durationSeconds: 120, label: "Timer 1")
                            TimerActivityManager.shared.createTimer(durationSeconds: 240, label: "Timer 2")
                            BatteryActivityMonitor.shared.triggerManualBatteryDisplay()
                            ShelfNearbyActivityBridge.shared.notifyItemsAdded(count: 5)
                            statusMessage = "Stacked 4 activities. Top 2 presented in split; rest in priority queue."
                        }
                    }

                    HStack(spacing: 10) {
                        Button("Consequential Approval (Locks Top)") {
                            let action = AgentAction(
                                appName: "Bank",
                                appIcon: "dollarsign.circle.fill",
                                title: "Send Wire Transfer ($500)",
                                subtitle: "Requires explicit user confirmation before executing.",
                                riskLevel: .high
                            )
                            appState.currentAction = action
                            activityCenter.isApprovalCardActive = true
                            activityCenter.start(ActivityOptions(
                                id: "consequential_demo",
                                label: "Approval: Wire Transfer",
                                priority: ActivityPriority.consequentialApproval,
                                alert: true,
                                content: ActivityContent(
                                    expanded: ActivityExpandedSlots(
                                        center: .text("Send Wire Transfer ($500)"),
                                        bottom: .text("Requires explicit user confirmation.")
                                    )
                                )
                            ))
                            statusMessage = "Consequential Approval Card locked on top (Priority 9999). Auto-dismiss and lower alerts locked out."
                        }
                        .foregroundColor(.yellow)

                        Button("Dismiss / Collapse") {
                            activityCenter.collapse()
                            statusMessage = "Collapsed active presentation."
                        }

                        Button("Reset All") {
                            activityCenter.reset()
                            TimerActivityManager.shared.cancelTimer()
                            RecordingActivityBridge.shared.stopRecording()
                            NowPlayingMediaManager.shared.clearMedia()
                            appState.currentAction = nil
                            statusMessage = "All activities ended. Notch returned to idle."
                        }
                        .foregroundColor(.red)
                    }
                }
                .padding(12)
                .background(Color.black.opacity(0.3))
                .cornerRadius(10)

                // Live Log
                Text("Log: \(statusMessage)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.gray)
                    .padding(.top, 4)
            }
            .padding(20)
        }
        .frame(minWidth: 540, minHeight: 520)
        .background(Color(red: 0.10, green: 0.10, blue: 0.12))
    }
}

