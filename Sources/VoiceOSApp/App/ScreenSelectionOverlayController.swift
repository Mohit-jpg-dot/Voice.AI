import AppKit
import SwiftUI
import VoiceOSCore

private final class SelectionOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    var onEscapePressed: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onEscapePressed?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onEscapePressed?()
            return
        }
        super.keyDown(with: event)
    }
}

public final class ScreenSelectionOverlayController: NSWindowController {
    private let appState: AppState
    private var selectionTool: CircleSelectionTool = .lasso
    private var isOverlayPresented: Bool = false
    private var isCursorPushed: Bool = false
    private var capturedFrontAppName: String = "Desktop"
    private var keyMonitor: Any?

    private var canvasView: ScreenSelectionCanvasView?
    private var toolbarContainer: NSVisualEffectView?
    private var toolButtons: [CircleSelectionTool: NSButton] = [:]

    public init(appState: AppState) {
        self.appState = appState

        let screenRect = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let panel = SelectionOverlayPanel(
            contentRect: screenRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        super.init(window: panel)

        panel.onEscapePressed = { [weak self] in
            self?.cancelFromUser()
        }

        setupOverlayContent(frame: NSRect(origin: .zero, size: screenRect.size))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func setupOverlayContent(frame: NSRect) {
        guard let panel = self.window else { return }

        let canvas = ScreenSelectionCanvasView(frame: frame)
        canvas.autoresizingMask = [.width, .height]
        canvas.activeTool = appState.activeSelectionTool
        canvas.onSelectionFinished = { [weak self] localBox, points, tool in
            self?.handleCompleteSelection(boundingBox: localBox, points: points, tool: tool)
        }
        canvas.onSelectionCancelled = { [weak self] in
            self?.cancelFromUser()
        }
        self.canvasView = canvas

        let toolbar = buildFloatingToolbar()
        canvas.addSubview(toolbar)
        self.toolbarContainer = toolbar

        panel.contentView = canvas
        layoutToolbar(in: frame.size)
        updateToolSelection(appState.activeSelectionTool)
    }

    private func buildFloatingToolbar() -> NSVisualEffectView {
        let effectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 500, height: 42))
        effectView.material = .hudWindow
        effectView.blendingMode = .withinWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 21
        effectView.layer?.borderWidth = 1.0
        effectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        effectView.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.85).cgColor

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: effectView.topAnchor, constant: 5),
            stack.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -5)
        ])

        let tools: [(CircleSelectionTool, String)] = [
            (.lasso, "Freehand Lasso"),
            (.rectangle, "Rectangle"),
            (.fullWindow, "Whole Window")
        ]

        for (tool, title) in tools {
            let btn = NSButton(title: title, target: self, action: #selector(toolButtonClicked(_:)))
            btn.bezelStyle = .rounded
            btn.isBordered = false
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 14
            btn.font = .systemFont(ofSize: 12, weight: .semibold)
            btn.contentTintColor = .white
            btn.tag = toolIndex(tool)
            btn.setContentHuggingPriority(.required, for: .horizontal)
            btn.widthAnchor.constraint(greaterThanOrEqualToConstant: 96).isActive = true
            btn.heightAnchor.constraint(equalToConstant: 28).isActive = true
            stack.addArrangedSubview(btn)
            toolButtons[tool] = btn
        }

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.widthAnchor.constraint(equalToConstant: 1).isActive = true
        divider.heightAnchor.constraint(equalToConstant: 18).isActive = true
        stack.addArrangedSubview(divider)

        let cancelBtn = NSButton(title: "Cancel (Esc)", target: self, action: #selector(cancelButtonClicked))
        cancelBtn.bezelStyle = .rounded
        cancelBtn.isBordered = false
        cancelBtn.wantsLayer = true
        cancelBtn.layer?.cornerRadius = 14
        cancelBtn.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
        cancelBtn.font = .systemFont(ofSize: 11.5, weight: .medium)
        cancelBtn.contentTintColor = NSColor.white.withAlphaComponent(0.85)
        cancelBtn.widthAnchor.constraint(greaterThanOrEqualToConstant: 88).isActive = true
        cancelBtn.heightAnchor.constraint(equalToConstant: 28).isActive = true
        stack.addArrangedSubview(cancelBtn)

        return effectView
    }

    private func layoutToolbar(in size: NSSize) {
        guard let toolbar = toolbarContainer else { return }
        let width: CGFloat = 450
        let height: CGFloat = 40
        let x = (size.width - width) / 2.0
        let y = size.height - height - 56.0
        toolbar.frame = NSRect(x: x, y: max(20, y), width: width, height: height)
    }

    private func toolIndex(_ tool: CircleSelectionTool) -> Int {
        switch tool {
        case .lasso: return 0
        case .rectangle: return 1
        case .elementSnap: return 2
        case .fullWindow: return 3
        }
    }

    private func toolFromIndex(_ tag: Int) -> CircleSelectionTool {
        switch tag {
        case 1: return .rectangle
        case 2: return .elementSnap
        case 3: return .fullWindow
        default: return .lasso
        }
    }

    @objc private func toolButtonClicked(_ sender: NSButton) {
        let tool = toolFromIndex(sender.tag)
        updateToolSelection(tool)
        if tool == .fullWindow {
            captureTopmostWindow()
        }
    }

    @objc private func cancelButtonClicked() {
        cancelFromUser()
    }

    private func cancelFromUser() {
        dismissOverlay()
        Task { @MainActor in
            appState.cancelCircleSelection()
        }
    }

    private func updateToolSelection(_ tool: CircleSelectionTool) {
        self.selectionTool = tool
        appState.activeSelectionTool = tool
        canvasView?.activeTool = tool

        for (t, btn) in toolButtons {
            let isSelected = (t == tool)
            btn.layer?.backgroundColor = isSelected
                ? NSColor.systemBlue.cgColor
                : NSColor.clear.cgColor
            btn.attributedTitle = NSAttributedString(
                string: btn.title,
                attributes: [
                    .foregroundColor: isSelected ? NSColor.white : NSColor.white.withAlphaComponent(0.80),
                    .font: NSFont.systemFont(ofSize: 12, weight: isSelected ? .bold : .medium)
                ]
            )
        }
    }

    public func presentOverlay() {
        guard !isOverlayPresented, let window = self.window else { return }
        isOverlayPresented = true

        // Remember the frontmost user app before our overlay shows
        let frontApp = NSWorkspace.shared.frontmostApplication
        if let name = frontApp?.localizedName, name != AppBrand.name {
            capturedFrontAppName = name
        } else {
            capturedFrontAppName = "Screen"
        }

        // Cover the screen where the mouse pointer currently is
        let mouseLoc = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLoc) }) ?? NSScreen.main ?? NSScreen.screens.first
        let screenRect = targetScreen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        window.setFrame(screenRect, display: true)
        layoutToolbar(in: screenRect.size)

        canvasView?.resetSelection()
        updateToolSelection(appState.activeSelectionTool)

        if !isCursorPushed {
            NSCursor.crosshair.push()
            isCursorPushed = true
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 {
                    self?.cancelFromUser()
                    return nil
                }
                return event
            }
        }
    }

    public func dismissOverlay() {
        guard isOverlayPresented else { return }
        isOverlayPresented = false

        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        if isCursorPushed {
            NSCursor.pop()
            isCursorPushed = false
        }
        canvasView?.resetSelection()
        window?.orderOut(nil)
    }

    private func captureTopmostWindow() {
        let myPID = ProcessInfo.processInfo.processIdentifier
        let screenRect = window?.frame ?? (NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900))
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screenRect.height

        var targetGlobalRect = screenRect
        var targetOwner = capturedFrontAppName

        if let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            for info in infoList {
                let layer = info[kCGWindowLayer as String] as? Int ?? -1
                let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t ?? 0
                if layer == 0 && ownerPID != myPID,
                   let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                   let cgBounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                   cgBounds.width > 80 && cgBounds.height > 80 {
                    // Convert Quartz top-left bounds to AppKit global bottom-left coords
                    targetGlobalRect = CGRect(
                        x: cgBounds.origin.x,
                        y: primaryHeight - cgBounds.origin.y - cgBounds.height,
                        width: cgBounds.width,
                        height: cgBounds.height
                    )
                    if let ownerName = info[kCGWindowOwnerName as String] as? String, !ownerName.isEmpty {
                        targetOwner = ownerName
                    }
                    break
                }
            }
        }

        let localRect = CGRect(
            x: targetGlobalRect.origin.x - screenRect.origin.x,
            y: targetGlobalRect.origin.y - screenRect.origin.y,
            width: targetGlobalRect.width,
            height: targetGlobalRect.height
        )
        capturedFrontAppName = targetOwner
        handleCompleteSelection(boundingBox: localRect, points: [], tool: .fullWindow)
    }

    public func handleCompleteSelection(boundingBox: CGRect, points: [CGPoint], tool: CircleSelectionTool) {
        let windowOrigin = window?.frame.origin ?? .zero
        let globalBox = CGRect(
            x: windowOrigin.x + boundingBox.origin.x,
            y: windowOrigin.y + boundingBox.origin.y,
            width: boundingBox.width,
            height: boundingBox.height
        )
        let appName = capturedFrontAppName

        dismissOverlay()

        Task {
            // Brief wait so macOS finishes hiding the overlay scrim before capturing
            try? await Task.sleep(nanoseconds: 90_000_000)

            let (analysis, pngData) = await ScreenVisionService.shared.captureRegionAndAnalyze(
                globalAppKitRect: globalBox,
                activeAppName: appName
            )

            let rawOCR = analysis.fullText.isEmpty ? analysis.summary : analysis.fullText
            let (cleanText, redactedCount) = RedactionRule.redactSensitiveData(from: rawOCR)

            let cropResult = ScreenCropResult(
                boundingBox: globalBox,
                lassoPoints: points,
                toolUsed: tool,
                extractedOCRText: cleanText,
                accessibilityRole: "AXRegion",
                redactedItemsCount: redactedCount,
                capturedImagePNGData: pngData,
                sourceAppName: analysis.activeAppTitle ?? appName
            )

            await MainActor.run {
                self.appState.completeCircleSelection(crop: cropResult)
            }
        }
    }
}

// MARK: - Interactive Selection Canvas View

private final class ScreenSelectionCanvasView: NSView {
    var activeTool: CircleSelectionTool = .lasso
    var onSelectionFinished: ((CGRect, [CGPoint], CircleSelectionTool) -> Void)?
    var onSelectionCancelled: (() -> Void)?

    private var isDragging = false
    private var startPoint: CGPoint = .zero
    private var currentPoint: CGPoint = .zero
    private var lassoPoints: [CGPoint] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    func resetSelection() {
        isDragging = false
        lassoPoints.removeAll()
        startPoint = .zero
        currentPoint = .zero
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        isDragging = true
        startPoint = pt
        currentPoint = pt
        lassoPoints = [pt]
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        let pt = convert(event.locationInWindow, from: nil)
        currentPoint = pt
        if let last = lassoPoints.last {
            let dx = pt.x - last.x
            let dy = pt.y - last.y
            if (dx * dx + dy * dy) >= 4.0 {
                lassoPoints.append(pt)
            }
        } else {
            lassoPoints.append(pt)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        let pt = convert(event.locationInWindow, from: nil)
        currentPoint = pt
        lassoPoints.append(pt)

        let box: CGRect
        if activeTool == .lasso && lassoPoints.count >= 3 {
            let xs = lassoPoints.map { $0.x }
            let ys = lassoPoints.map { $0.y }
            let minX = xs.min() ?? pt.x
            let maxX = xs.max() ?? pt.x
            let minY = ys.min() ?? pt.y
            let maxY = ys.max() ?? pt.y
            box = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        } else {
            box = CGRect(
                x: min(startPoint.x, pt.x),
                y: min(startPoint.y, pt.y),
                width: abs(pt.x - startPoint.x),
                height: abs(pt.y - startPoint.y)
            )
        }

        if box.width >= 14 && box.height >= 14 {
            onSelectionFinished?(box, lassoPoints, activeTool)
        } else {
            resetSelection()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onSelectionCancelled?()
            return
        }
        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Subtle dark scrim
        NSColor.black.withAlphaComponent(0.32).setFill()
        bounds.fill()

        // Helper hint text at top when idle
        if !isDragging {
            let hint = "Circle or drag over anything on screen to Ask • Press Esc to cancel"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.82)
            ]
            let size = hint.size(withAttributes: attrs)
            let rect = NSRect(
                x: (bounds.width - size.width) / 2.0,
                y: bounds.height - 120.0,
                width: size.width,
                height: size.height
            )
            hint.draw(in: rect, withAttributes: attrs)
            return
        }

        let glowColor = NSColor(calibratedRed: 0.22, green: 0.74, blue: 0.97, alpha: 1.0)
        let fillColor = NSColor(calibratedRed: 0.22, green: 0.74, blue: 0.97, alpha: 0.14)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(calibratedRed: 0.0, green: 0.44, blue: 0.89, alpha: 0.85)
        shadow.shadowBlurRadius = 10
        shadow.shadowOffset = .zero
        shadow.set()

        if activeTool == .lasso, lassoPoints.count > 1 {
            let path = NSBezierPath()
            path.lineWidth = 3.0
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: lassoPoints[0])
            for pt in lassoPoints.dropFirst() {
                path.line(to: pt)
            }

            let fillPath = path.copy() as! NSBezierPath
            fillPath.close()
            fillColor.setFill()
            fillPath.fill()

            glowColor.setStroke()
            path.stroke()
        } else {
            let rect = CGRect(
                x: min(startPoint.x, currentPoint.x),
                y: min(startPoint.y, currentPoint.y),
                width: abs(currentPoint.x - startPoint.x),
                height: abs(currentPoint.y - startPoint.y)
            )
            let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
            path.lineWidth = 2.5

            fillColor.setFill()
            path.fill()

            glowColor.setStroke()
            path.stroke()

            // Live dimension pill
            let dimText = "\(Int(rect.width)) × \(Int(rect.height))"
            let dimAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
            let dimSize = dimText.size(withAttributes: dimAttrs)
            let pillRect = NSRect(
                x: rect.maxX - dimSize.width - 14,
                y: max(12, rect.minY - 26),
                width: dimSize.width + 12,
                height: 20
            )
            NSColor.black.withAlphaComponent(0.75).setFill()
            NSBezierPath(roundedRect: pillRect, xRadius: 6, yRadius: 6).fill()
            dimText.draw(at: NSPoint(x: pillRect.minX + 6, y: pillRect.minY + 3), withAttributes: dimAttrs)
        }

        NSGraphicsContext.restoreGraphicsState()
    }
}
