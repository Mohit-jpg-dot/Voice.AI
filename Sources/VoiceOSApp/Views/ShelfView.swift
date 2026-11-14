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
    @State private var quickLookItemURL: URL? = nil

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 6) {
            // MARK: - Sub-Header / Action Bar
            headerBar

            // MARK: - Main Area (Tiles or Empty Drop Zone)
            if items.isEmpty {
                emptyDropZone
            } else {
                tilesScrollView
            }

            // MARK: - Floating Selection Actions Bar (when items selected)
            if !selectedItemIDs.isEmpty && !items.isEmpty {
                selectionActionBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 12)
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
        // Native Keyboard Shortcuts
        .background(
            Group {
                Button(action: selectAll) { EmptyView() }
                    .keyboardShortcut("a", modifiers: [.command])
                Button(action: handleCopySelected) { EmptyView() }
                    .keyboardShortcut("c", modifiers: [.command])
                Button(action: handlePasteClipboard) { EmptyView() }
                    .keyboardShortcut("v", modifiers: [.command])
                Button(action: handleQuickLookSelected) { EmptyView() }
                    .keyboardShortcut(.space, modifiers: [])
                Button(action: handleRemoveSelected) { EmptyView() }
                    .keyboardShortcut(.delete, modifiers: [])
            }
            .frame(width: 0, height: 0)
            .opacity(0)
        )
        // Trash Confirmation Sheet
        .alert("Move to Trash?", isPresented: $showingTrashConfirmation) {
            Button("Cancel", role: .cancel) { itemToTrash = nil }
            Button("Move to Trash", role: .destructive) {
                if let item = itemToTrash {
                    performMoveToTrash(item)
                }
            }
        } message: {
            Text("Are you sure you want to move '\(itemToTrash?.displayName ?? "this file")' to the macOS Trash? You can restore it from Trash at any time.")
        }
    }

    // MARK: - Header Bar (Minimal, Glassmorphic, Apple-grade)
    private var headerBar: some View {
        HStack(alignment: .center, spacing: 6) {
            // Left Status Pill
            HStack(spacing: 5) {
                Image(systemName: "tray.2.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(DesignTokens.Colors.accentCyan)

                if selectedItemIDs.isEmpty {
                    if items.isEmpty {
                        Text("STAGING TRAY")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundColor(Color.white.opacity(0.60))
                    } else {
                        Text("\(items.count) \(items.count == 1 ? "ITEM" : "ITEMS")")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundColor(Color.white.opacity(0.80))
                    }
                } else {
                    Text("\(selectedItemIDs.count) SELECTED")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundColor(DesignTokens.Colors.accentCyan)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.06))
            .clipShape(Capsule())

            Spacer()

            // Right Action Icon Buttons
            HStack(spacing: 5) {
                // Paste Clipboard (⌘V)
                Button(action: handlePasteClipboard) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.75))
                        .frame(width: 22, height: 22)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Paste from clipboard into shelf (⌘V)")

                if !items.isEmpty {
                    // Select All / Deselect
                    Button(action: toggleSelectAll) {
                        Image(systemName: selectedItemIDs.count == items.count ? "checkmark.circle.fill" : "checkmark.circle")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(selectedItemIDs.count == items.count ? DesignTokens.Colors.accentCyan : Color.white.opacity(0.75))
                            .frame(width: 22, height: 22)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Select all (⌘A)")

                    // Clear Shelf
                    Button(action: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            ShelfStore.shared.clear()
                            refreshItems()
                        }
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.55))
                            .frame(width: 22, height: 22)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Clear shelf")
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    // MARK: - Empty Drop Zone (Sleek Apple Glass Drop Target)
    private var emptyDropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    isTargetedForDrop
                        ? DesignTokens.Colors.accentCyan.opacity(0.12)
                        : Color.white.opacity(0.03)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            isTargetedForDrop
                                ? DesignTokens.Colors.accentCyan
                                : Color.white.opacity(0.12),
                            style: StrokeStyle(lineWidth: isTargetedForDrop ? 1.8 : 1.0, dash: isTargetedForDrop ? [] : [6, 4])
                        )
                )

            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(isTargetedForDrop ? DesignTokens.Colors.accentCyan.opacity(0.20) : Color.white.opacity(0.06))
                        .frame(width: 38, height: 38)

                    Image(systemName: isTargetedForDrop ? "arrow.down.circle.fill" : "tray.and.arrow.down")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(isTargetedForDrop ? DesignTokens.Colors.accentCyan : Color.white.opacity(0.65))
                }

                VStack(spacing: 2) {
                    Text(isTargetedForDrop ? "Release to Drop on Shelf" : "Drop files, links, or text here")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isTargetedForDrop ? DesignTokens.Colors.accentCyan : Color.white.opacity(0.90))

                    Text("Drag files near the notch anytime to stage them while working")
                        .font(.system(size: 9.5, weight: .regular))
                        .foregroundColor(Color.white.opacity(0.45))
                }

                // Keyboard Helper Badges
                HStack(spacing: 8) {
                    hintBadge(title: "⌘V Paste")
                    hintBadge(title: "Option-drag to Move")
                    hintBadge(title: "Space to Preview")
                }
                .padding(.top, 2)
            }
            .padding(.vertical, 10)
        }
        .frame(height: 116)
        .padding(.bottom, 4)
        .onDrop(of: [UTType.item.identifier], isTargeted: $isTargetedForDrop) { providers in
            handleDropProviders(providers)
            return true
        }
    }

    private func hintBadge(title: String) -> some View {
        Text(title)
            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
            .foregroundColor(Color.white.opacity(0.55))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.06))
            .clipShape(Capsule())
    }

    // MARK: - Tiles Scroll View
    private var tilesScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 8) {
                ForEach(items) { item in
                    ShelfTileCard(
                        item: item,
                        isSelected: selectedItemIDs.contains(item.id),
                        onSelect: { isMulti, isRange in
                            handleSelect(item: item, isMulti: isMulti, isRange: isRange)
                        },
                        onOpen: {
                            openItem(item)
                        },
                        onQuickRemove: {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                ShelfStore.shared.removeItem(byId: item.id)
                                refreshItems()
                            }
                        },
                        onTrashRequest: {
                            itemToTrash = item
                            showingTrashConfirmation = true
                        },
                        onQuickLook: {
                            quickLookItem(item)
                        }
                    )
                    // Drag Out Provider
                    .onDrag {
                        createItemProvider(for: item)
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
        .frame(height: 104)
        .onDrop(of: [UTType.item.identifier], isTargeted: $isTargetedForDrop) { providers in
            handleDropProviders(providers)
            return true
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isTargetedForDrop ? DesignTokens.Colors.accentCyan : Color.clear, lineWidth: 2)
        )
    }

    // MARK: - Floating Selection Actions Bar
    private var selectionActionBar: some View {
        HStack(spacing: 8) {
            Text("\(selectedItemIDs.count) selected")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundColor(DesignTokens.Colors.accentCyan)
                .padding(.leading, 4)

            Spacer()

            // Quick Look
            Button(action: handleQuickLookSelected) {
                HStack(spacing: 3) {
                    Image(systemName: "eye")
                        .font(.system(size: 9))
                    Text("Preview (Space)")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(Color.white.opacity(0.10))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            // Copy
            Button(action: handleCopySelected) {
                HStack(spacing: 3) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9))
                    Text("Copy (⌘C)")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(Color.white.opacity(0.10))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            // AirDrop
            Button(action: handleAirDropSelected) {
                HStack(spacing: 3) {
                    Image(systemName: "airdrop")
                        .font(.system(size: 9))
                    Text("AirDrop")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundColor(DesignTokens.Colors.accentCyan)
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(DesignTokens.Colors.accentCyan.opacity(0.18))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            // Remove
            Button(action: handleRemoveSelected) {
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundColor(.white.opacity(0.60))
                    .frame(width: 18, height: 18)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Remove selected items")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.65))
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.6)
                )
        )
    }

    // MARK: - Actions & Handlers
    private func refreshItems() {
        items = ShelfStore.shared.getItems()
        selectedItemIDs = selectedItemIDs.filter { id in items.contains(where: { $0.id == id }) }
    }

    private func selectAll() {
        selectedItemIDs = Set(items.map { $0.id })
    }

    private func toggleSelectAll() {
        if selectedItemIDs.count == items.count {
            selectedItemIDs.removeAll()
        } else {
            selectedItemIDs = Set(items.map { $0.id })
        }
    }

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

    private func openItem(_ item: ShelfItem) {
        if let url = ShelfStore.shared.resolveURL(for: item) {
            NSWorkspace.shared.open(url)
        } else if let u = item.urlString, let web = URL(string: u) {
            NSWorkspace.shared.open(web)
        }
    }

    private func quickLookItem(_ item: ShelfItem) {
        if let url = ShelfStore.shared.resolveURL(for: item) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
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

    private func handleRemoveSelected() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            for id in selectedItemIDs {
                ShelfStore.shared.removeItem(byId: id)
            }
            refreshItems()
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

    // MARK: - Drag Providers & Drop Destination
    private func createItemProvider(for item: ShelfItem) -> NSItemProvider {
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
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let fileURL = url {
                        DispatchQueue.main.async {
                            ShelfStore.shared.addFileURL(fileURL, sourceAppName: "Drop")
                            self.refreshItems()
                        }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let webURL = url {
                        DispatchQueue.main.async {
                            ShelfStore.shared.addWebURL(webURL, sourceAppName: "Drop")
                            self.refreshItems()
                        }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
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

// MARK: - Professional Apple Glass Tile Card
public struct ShelfTileCard: View {
    public let item: ShelfItem
    public let isSelected: Bool
    public let onSelect: (Bool, Bool) -> Void
    public let onOpen: () -> Void
    public let onQuickRemove: () -> Void
    public let onTrashRequest: () -> Void
    public let onQuickLook: () -> Void

    @State private var thumbnail: NSImage? = nil
    @State private var isHovered: Bool = false

    public var body: some View {
        Button(action: {
            let isCmd = NSEvent.modifierFlags.contains(.command)
            let isShift = NSEvent.modifierFlags.contains(.shift)
            onSelect(isCmd, isShift)
        }) {
            VStack(spacing: 4) {
                // Top Icon / Thumbnail Container
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isHovered ? 0.12 : 0.07),
                                    Color.white.opacity(isHovered ? 0.06 : 0.03)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 70, height: 56)

                    if let thumb = thumbnail {
                        Image(nsImage: thumb)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 58, height: 48)
                            .cornerRadius(7)
                            .shadow(color: Color.black.opacity(0.30), radius: 3, x: 0, y: 1.5)
                    } else {
                        VStack(spacing: 2) {
                            Image(systemName: item.kind.iconName)
                                .font(.system(size: 22, weight: .light))
                                .foregroundColor(kindColor)

                            if let ext = fileExtensionBadge {
                                Text(ext)
                                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.75))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.white.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }
                    }

                    // Unavailable Error Badge
                    if item.isUnavailable {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.yellow)
                            .padding(2)
                            .background(Color.black.opacity(0.85))
                            .clipShape(Circle())
                            .offset(x: -3, y: 3)
                    }

                    // Hover Quick-Remove "×" Button
                    if isHovered {
                        Button(action: onQuickRemove) {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 16, height: 16)
                                .background(Color.black.opacity(0.75))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .offset(x: -2, y: 2)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: 70, height: 56)

                // Title Label (middle truncation preserves extensions like report...pdf)
                Text(item.displayName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(item.isUnavailable ? Color.white.opacity(0.40) : Color.white.opacity(0.95))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 72)

                // File Size / Subtext
                Text(item.isUnavailable ? "Missing" : item.formattedSize)
                    .font(.system(size: 8.5, weight: .regular))
                    .foregroundColor(item.isUnavailable ? Color.red.opacity(0.85) : Color.white.opacity(0.50))
                    .lineLimit(1)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        isSelected
                            ? DesignTokens.Colors.accentBlue.opacity(0.25)
                            : (isHovered ? Color.white.opacity(0.06) : Color.white.opacity(0.02))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected
                            ? DesignTokens.Colors.accentBlue
                            : (isHovered ? Color.white.opacity(0.18) : Color.white.opacity(0.08)),
                        lineWidth: isSelected ? 1.5 : 0.6
                    )
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                onOpen()
            }
        )
        .contextMenu {
            Button("Open") { onOpen() }
            Button("Quick Look (Space)") { onQuickLook() }
            Button("Reveal in Finder") {
                if let url = ShelfStore.shared.resolveURL(for: item) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            Divider()
            Button("Remove from Shelf") { onQuickRemove() }
            Button("Move to Trash...") { onTrashRequest() }
        }
        .onAppear {
            loadThumbnail()
        }
    }

    private var kindColor: Color {
        if item.isUnavailable { return .red }
        switch item.kind {
        case .file: return DesignTokens.Colors.accentBlue
        case .folder: return DesignTokens.Colors.accentAmber
        case .image: return DesignTokens.Colors.accentPurple
        case .textSnippet: return DesignTokens.Colors.accentGreen
        case .url: return DesignTokens.Colors.accentCyan
        }
    }

    private var fileExtensionBadge: String? {
        let name = item.displayName
        if let dotIdx = name.lastIndex(of: "."), dotIdx != name.startIndex {
            let ext = String(name[name.index(after: dotIdx)...]).uppercased()
            if ext.count <= 4 && ext.rangeOfCharacter(from: .letters) != nil {
                return ext
            }
        }
        return nil
    }

    private func loadThumbnail() {
        if let url = ShelfStore.shared.resolveURL(for: item) {
            Task {
                let img = await ShelfThumbnailCache.shared.requestThumbnail(for: url, size: CGSize(width: 70, height: 56))
                await MainActor.run {
                    self.thumbnail = img
                }
            }
        }
    }
}
