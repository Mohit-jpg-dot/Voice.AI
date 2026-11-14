// Ported from islandcn, MIT License, Copyright (c) 2026 Leo. Modified for Swift.
// Shelf storage and AirDrop sharing activity bridge.

import Foundation

@MainActor
public final class ShelfNearbyActivityBridge: ObservableObject {
    public static let shared = ShelfNearbyActivityBridge()

    private init() {}

    public func notifyItemsAdded(count: Int) {
        guard count > 0 else { return }

        let leading: ActivitySlotContent = .symbol(name: "tray.and.arrow.down.fill", tint: "cyan")
        let trailing: ActivitySlotContent = .text("+\(count)")

        let expanded = ActivityExpandedSlots(
            leading: leading,
            trailing: trailing,
            center: .text("Shelf"),
            bottom: .text("\(count) \(count == 1 ? "item" : "items") added")
        )

        let content = ActivityContent(
            compact: ActivityCompactSlots(leading: leading, trailing: trailing),
            minimal: .symbol(name: "tray.fill", tint: "cyan"),
            expanded: expanded
        )

        ActivityCenter.shared.start(ActivityOptions(
            id: "shelf-nearby-transfer",
            label: "Shelf Updated",
            priority: ActivityPriority.standard,
            alert: false,
            isSensitive: false,
            content: content
        ))
    }

    public func notifyAirDropShareOpened(itemCount: Int) {
        let leading: ActivitySlotContent = .symbol(name: "airdrop", tint: "blue")
        let trailing: ActivitySlotContent = .text("Sharing")

        let expanded = ActivityExpandedSlots(
            leading: leading,
            trailing: trailing,
            center: .text("AirDrop"),
            bottom: .text("Share sheet opened for \(itemCount) \(itemCount == 1 ? "item" : "items")")
        )

        let content = ActivityContent(
            compact: ActivityCompactSlots(leading: leading, trailing: trailing),
            minimal: .symbol(name: "airdrop", tint: "blue"),
            expanded: expanded
        )

        ActivityCenter.shared.start(ActivityOptions(
            id: "airdrop-share",
            label: "AirDrop Sharing",
            priority: ActivityPriority.standard,
            alert: false,
            isSensitive: false,
            content: content
        ))
    }
}

