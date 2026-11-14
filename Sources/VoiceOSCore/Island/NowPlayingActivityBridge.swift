// Ported from islandcn, MIT License, Copyright (c) 2026 Leo. Modified for Swift.
// Media playback activity bridge connecting NowPlayingMediaManager with ActivityCenter.

import Foundation
import Combine

@MainActor
public final class NowPlayingActivityBridge: ObservableObject {
    public static let shared = NowPlayingActivityBridge()

    private var cancellables = Set<AnyCancellable>()
    private let activityId = "now-playing"

    private init() {
        bindMediaUpdates()
    }

    private func bindMediaUpdates() {
        let existingCallback = NowPlayingMediaManager.shared.onMediaChanged
        NowPlayingMediaManager.shared.onMediaChanged = { [weak self] media in
            existingCallback?(media)
            Task { @MainActor [weak self] in
                self?.handleMediaUpdate(media)
            }
        }
        if let current = NowPlayingMediaManager.shared.currentMedia {
            handleMediaUpdate(current)
        }
    }

    private func handleMediaUpdate(_ media: NowPlayingItem?) {
        guard let media = media, media.isPlaying else {
            ActivityCenter.shared.end(id: activityId)
            return
        }

        let leading: ActivitySlotContent = .symbol(
            name: media.source == .spotify ? "spotify" : "play.rectangle.fill",
            tint: media.source == .spotify ? "green" : "red"
        )
        let trailing: ActivitySlotContent = .waveform(levels: [0.6, 0.9, 0.4, 0.8, 0.5], active: true)

        let expanded = ActivityExpandedSlots(
            leading: leading,
            trailing: .text(String(format: "%d:%02d", media.positionSeconds / 60, media.positionSeconds % 60)),
            center: .text(media.title),
            bottom: .text(media.artistOrChannel.isEmpty ? media.source.rawValue : media.artistOrChannel)
        )

        let content = ActivityContent(
            compact: ActivityCompactSlots(leading: leading, trailing: trailing),
            minimal: leading,
            expanded: expanded
        )

        ActivityCenter.shared.start(ActivityOptions(
            id: activityId,
            label: "\(media.title) - \(media.artistOrChannel)",
            priority: ActivityPriority.media,
            alert: false,
            isSensitive: false,
            content: content,
            onPress: {
                NowPlayingMediaManager.shared.togglePlayPause()
            }
        ))
    }
}
