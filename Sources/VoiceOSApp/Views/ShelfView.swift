import SwiftUI
import AppKit
import UniformTypeIdentifiers
import QuickLookUI
import VoiceOSCore

public struct ShelfView: View {
    @ObservedObject var appState: AppState
    @State private var items: [ShelfItem] = []
    @State private var selectedItemIDs: Set<UUID> = []
    @State private var isTargetedForDrop: Bool = false
    @State private var showingTrashConfirmation: Bool = false
    @State private var itemToTrash: ShelfItem? = nil
    @State private var statusMessage: String? = nil
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.colorSchemeContrast) var colorContrast

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 8) {
            // Header: Shelf Title & Action Buttons
            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "tray.2.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(DesignTokens.Colors.accentBlue)

                    Text("SHELF")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.9))

                    if !items.isEmpty {
                        Text("\(items.count)")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                Spacer()

                // Actions: Paste, AirDrop, Clear All
                HStack(spacing: 6) {
                    Button(action: handlePasteClipboard) {
                        HStack(spacing: 3) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 9.5))
                            Text("Paste (⌘V)")
                                .font(.system(size: 9.5, weight: .medium))
                        }
                        .foregroundColor(.white.opacity(0.75))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .help("Paste files or text from clipboard into shelf")

                    if !selectedItemIDs.isEmpty {
                        Button(action: handleAirDropSelected) {
                            HStack(spacing: 3) {
                                Image(systemName: "airdrop")
                                    .font(.system(size: 10))
                                Text("AirDrop")
                                    .font(.system(size: 9.5, weight: .medium))
                            }
                            .foregroundColor(DesignTokens.Colors.accentCyan)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(DesignTokens.Colors.accentCyan.opacity(0.15))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .help("AirDrop selected items")
                    }

                    if !items.isEmpty {
                        Button(action: {
                            ShelfStore.shared.clear()
                            refreshItems()
                        }) {
                            Text("Clear")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundColor(.white.opacity(0.55))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.06))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .help("Clear all items from shelf")
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)

            // Main Content Area: Empty State or Grid of Tiles
            if items.isEmpty {
                emptyDropZone
            } else {
                tilesGrid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            refreshItems()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshItems()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("VoiceOS.ShelfItemsUpdated"))) { _ in
            refreshItems()
        }
        .onChange(of: appState.isShelfDragTargetHovered) { _, hovered in
            withAnimation(.easeInOut(duration: 0.2)) {
                isTargetedForDrop = hovered
            }
        }
        // Keyboard Shortcuts
        .background(
            Group {
                Button(action: { selectedItemIDs = Set(items.map { $0.id }) }) { EmptyView() }
                    .keyboardShortcut("a", modifiers: [.command])
                Button(action: handleCopySelected) { EmptyView() }
                    .keyboardShortcut("c", modifiers: [.command])
                Button(action: handlePasteClipboard) { EmptyView() }
                    .keyboardShortcut("v", modifiers: [.command])
                Button(action: handleQuickLookSelected) { EmptyView() }
                    .keyboardShortcut(.space, modifiers: [])
            }
            .frame(width: 0, height: 0)
            .opacity(0)
        )
        .alert("Move to Trash?", isPresented: $showingTrashConfirmation) {
            Button("Cancel", role: .cancel) { itemToTrash = nil }
            Button("Move to Trash", role: .destructive) {
                if let item = itemToTrash {
                    performMoveToTrash(item)
                }
            }
        } message: {
            Text("Are you sure you want to move '\(itemToTrash?.displayName ?? "this file")' to the macOS Trash? You can put it back from Trash at any time.")
        }
    }

    // MARK: - Empty State (Dashed Outline Drop Target)
    private var emptyDropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isTargetedForDrop ? DesignTokens.Colors.accentCyan : Color.white.opacity(0.18),
                    style: StrokeStyle(lineWidth: isTargetedForDrop ? 2.0 : 1.2, dash: [6, 4])
                )
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isTargetedForDrop ? DesignTokens.Colors.accentCyan.opacity(0.10) : Color.white.opacity(0.03))
                )

            VStack(spacing: 6) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 20, weight: .light))
                    .foregroundColor(isTargetedForDrop ? DesignTokens.Colors.accentCyan : Color.white.opacity(0.45))

                Text(isTargetedForDrop ? "Drop to Add to Shelf" : "Drop files, links, or text here")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.65))
            }
        }
        .frame(height: 100)
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
        .onDrop(of: [UTType.item.identifier], isTargeted: $isTargetedForDrop) { providers in
            handleDropProviders(providers)
            return true
        }
    }

    // MARK: - Tiles Grid View
    private var tilesGrid: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 8) {
                ForEach(items) { item in
                    ShelfTileView(
                        item: item,
                        isSelected: selectedItemIDs.contains(item.id),
                        onSelect: { isMulti, isRange in
                            handleSelect(item: item, isMulti: isMulti, isRange: isRange)
                        },
                        onOpen: {
                            openItem(item)
                        },
                        onRemove: {
                            ShelfStore.shared.removeItem(byId: item.id)
                            refreshItems()
                        },
                        onTrashRequest: {
                            itemToTrash = item
                            showingTrashConfirmation = true
                        },
                        onQuickLook: {
                            quickLookItem(item)
                        },
                        onShare: { view in
                            presentShareSheet(for: item, from: view)
                        }
                    )
                    // Drag Out Support: Multi-Item or Single Item
                    .onDrag {
                        let provider = createItemProvider(for: item)
                        return provider
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
        }
        .frame(height: 115)
        .onDrop(of: [UTType.item.identifier], isTargeted: $isTargetedForDrop) { providers in
            handleDropProviders(providers)
            return true
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isTargetedForDrop ? DesignTokens.Colors.accentCyan : Color.clear, lineWidth: 2)
                .padding(.horizontal, 10)
        )
    }

    // MARK: - Selection Handling
    private func handleSelect(item: ShelfItem, isMulti: Bool, isRange: Bool) {
        if isMulti {
            if selectedItemIDs.contains(item.id) {
                selectedItemIDs.remove(item.id)
            } else {
                selectedItemIDs.insert(item.id)
            }
        } else if isRange, let lastID = selectedItemIDs.first, let idxA = items.firstIndex(where: { $0.id == lastID }), let idxB = items.firstIndex(where: { $0.id == item.id }) {
            let start = min(idxA, idxB)
            let end = max(idxA, idxB)
            for idx in start...end {
                selectedItemIDs.insert(items[idx].id)
            }
        } else {
            selectedItemIDs = [item.id]
        }
    }

    // MARK: - Actions
    private func refreshItems() {
        self.items = ShelfStore.shared.getItems()
    }

    private func openItem(_ item: ShelfItem) {
        if let url = ShelfStore.shared.resolveURL(for: item) {
            NSWorkspace.shared.open(url)
        } else if let u = item.urlString, let web = URL(string: u) {
            NSWorkspace.shared.open(web)
        } else if let text = item.textContent {
            // Copy text to pasteboard
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    private func quickLookItem(_ item: ShelfItem) {
        if let url = ShelfStore.shared.resolveURL(for: item) {
            NSWorkspace.shared.open(url)
        }
    }

    private func handleQuickLookSelected() {
        guard let firstID = selectedItemIDs.first, let item = items.first(where: { $0.id == firstID }) else { return }
        quickLookItem(item)
    }

    private func handleCopySelected() {
        let selectedItems = items.filter { selectedItemIDs.contains($0.id) }
        guard !selectedItems.isEmpty else { return }

        let pb = NSPasteboard.general
        pb.clearContents()

        let urls = selectedItems.compactMap { ShelfStore.shared.resolveURL(for: $0) }
        if !urls.isEmpty {
            pb.writeObjects(urls as [NSURL])
        } else {
            let texts = selectedItems.compactMap { $0.textContent }
            if !texts.isEmpty {
                pb.setString(texts.joined(separator: "\n"), forType: .string)
            }
        }
    }

    private func handlePasteClipboard() {
        let pb = NSPasteboard.general
        Task {
            _ = await ShelfDropController.shared.processPasteboard(pb, sourceAppName: "Clipboard")
            await MainActor.run {
                refreshItems()
            }
        }
    }

    private func handleAirDropSelected() {
        let selectedItems = items.filter { selectedItemIDs.contains($0.id) }
        let urls = selectedItems.compactMap { ShelfStore.shared.resolveURL(for: $0) }
        guard !urls.isEmpty else { return }

        if let sharingService = NSSharingService(named: .sendViaAirDrop) {
            if sharingService.canPerform(withItems: urls) {
                sharingService.perform(withItems: urls)
            }
        }
    }

    private func performMoveToTrash(_ item: ShelfItem) {
        if let url = ShelfStore.shared.resolveURL(for: item) {
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
        ShelfStore.shared.removeItem(byId: item.id)
        refreshItems()
        itemToTrash = nil
    }

    private func presentShareSheet(for item: ShelfItem, from view: NSView) {
        guard let url = ShelfStore.shared.resolveURL(for: item) else { return }
        let picker = NSSharingServicePicker(items: [url])
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
    }

    // MARK: - Drag Providers & Drop Destination
    private func createItemProvider(for item: ShelfItem) -> NSItemProvider {
        // Option drag move vs default copy
        let isOptionDown = NSEvent.modifierFlags.contains(.option)
        let isMoveDefault = ShelfStore.shared.settings.defaultDragOutAction == .move
        let shouldMove = isOptionDown ? !isMoveDefault : isMoveDefault

        if let url = ShelfStore.shared.resolveURL(for: item) {
            let provider = NSItemProvider(contentsOf: url) ?? NSItemProvider()
            if shouldMove || ShelfStore.shared.settings.removeAfterDragOut {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    ShelfStore.shared.removeItem(byId: item.id)
                    self.refreshItems()
                }
            }
            return provider
        } else if let text = item.textContent {
            let provider = NSItemProvider(object: text as NSString)
            if shouldMove || ShelfStore.shared.settings.removeAfterDragOut {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    ShelfStore.shared.removeItem(byId: item.id)
                    self.refreshItems()
                }
            }
            return provider
        } else if let u = item.urlString, let web = URL(string: u) {
            let provider = NSItemProvider(object: web as NSURL)
            return provider
        }
        return NSItemProvider()
    }

    private func handleDropProviders(_ providers: [NSItemProvider]) {
        for provider in providers {
            // 1. File URL
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let fileURL = url {
                        DispatchQueue.main.async {
                            ShelfStore.shared.addFileURL(fileURL, sourceAppName: "Drop")
                            self.refreshItems()
                        }
                    }
                }
            }
            // 2. URL
            else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let webURL = url {
                        DispatchQueue.main.async {
                            ShelfStore.shared.addWebURL(webURL, sourceAppName: "Drop")
                            self.refreshItems()
                        }
                    }
                }
            }
            // 3. Plain Text
            else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                _ = provider.loadObject(ofClass: String.self) { str, _ in
                    if let text = str {
                        DispatchQueue.main.async {
                            ShelfStore.shared.addTextSnippet(text, sourceAppName: "Drop")
                            self.refreshItems()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Individual Tile View
public struct ShelfTileView: View {
    public let item: ShelfItem
    public let isSelected: Bool
    public let onSelect: (Bool, Bool) -> Void
    public let onOpen: () -> Void
    public let onRemove: () -> Void
    public let onTrashRequest: () -> Void
    public let onQuickLook: () -> Void
    public let onShare: (NSView) -> Void

    @State private var thumbnail: NSImage? = nil

    public var body: some View {
        Button(action: {
            let isCmd = NSEvent.modifierFlags.contains(.command)
            let isShift = NSEvent.modifierFlags.contains(.shift)
            onSelect(isCmd, isShift)
        }) {
            VStack(spacing: 4) {
                // Top Icon / Thumbnail Container
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 64, height: 56)

                    if let thumb = thumbnail {
                        Image(nsImage: thumb)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 52, height: 48)
                            .cornerRadius(6)
                    } else {
                        Image(systemName: item.kind.iconName)
                            .font(.system(size: 22))
                            .foregroundColor(item.isUnavailable ? Color.red : Color.white.opacity(0.75))
                    }

                    // Unavailable Badge
                    if item.isUnavailable {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.yellow)
                            .padding(2)
                            .background(Color.black.opacity(0.8))
                            .clipShape(Circle())
                            .offset(x: -3, y: 3)
                    }
                }
                .frame(width: 64, height: 56)

                // Title & Size / Unavailable Label
                Text(item.displayName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(item.isUnavailable ? Color.white.opacity(0.4) : Color.white)
                    .lineLimit(1)
                    .frame(width: 68)

                Text(item.isUnavailable ? "Unavailable" : item.formattedSize)
                    .font(.system(size: 8, weight: .regular))
                    .foregroundColor(item.isUnavailable ? Color.red.opacity(0.8) : Color.white.opacity(0.50))
                    .lineLimit(1)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? DesignTokens.Colors.accentBlue.opacity(0.25) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isSelected ? DesignTokens.Colors.accentBlue : Color.white.opacity(0.10),
                        lineWidth: isSelected ? 1.5 : 0.6
                    )
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open") { onOpen() }
            Button("Quick Look (Space)") { onQuickLook() }
            Button("Reveal in Finder") {
                if let url = ShelfStore.shared.resolveURL(for: item) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            Divider()
            Button("Remove from Shelf") { onRemove() }
            Button("Move to Trash...") { onTrashRequest() }
        }
        .onAppear {
            loadThumbnail()
        }
        .accessibilityLabel(Text("\(item.displayName), \(item.formattedSize)"))
        .accessibilityHint(Text("Double click to open, space for Quick Look, or drag into other apps."))
    }

    private func loadThumbnail() {
        if let url = ShelfStore.shared.resolveURL(for: item) {
            Task {
                let img = await ShelfThumbnailCache.shared.requestThumbnail(for: url, size: CGSize(width: 64, height: 64))
                await MainActor.run {
                    self.thumbnail = img
                }
            }
        }
    }
}

