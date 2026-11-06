import AppKit
import Carbon

/// Inserts dictated text universally into any frontmost application (Notes, TextEdit, Slack, VS Code, Chrome, etc.)
/// Preserves the user's existing clipboard contents and restores them cleanly after paste.
public final class UniversalTextInserter: @unchecked Sendable {
    public static let shared = UniversalTextInserter()

    public init() {}

    /// Inserts text into the current cursor location in the frontmost application.
    public func insertText(_ text: String, completion: (@Sendable (Bool) -> Void)? = nil) {
        guard !text.isEmpty else {
            completion?(false)
            return
        }

        let pasteboard = NSPasteboard.general
        
        // 1. Preserve existing clipboard contents
        let previousItems: [(NSPasteboard.PasteboardType, Data)] = pasteboard.pasteboardItems?.flatMap { item in
            item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            }
        } ?? []

        // 2. Put new text on pasteboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // 3. Synthesize Cmd+V key event to paste into the active focused element
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.synthesizePasteCommand()

            // 4. Restore original clipboard contents after paste has been processed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                if !previousItems.isEmpty {
                    pasteboard.clearContents()
                    for (type, data) in previousItems {
                        pasteboard.setData(data, forType: type)
                    }
                }
                completion?(true)
            }
        }
    }

    private func synthesizePasteCommand() {
        let vKeyCode: CGKeyCode = 0x09 // Virtual key code for 'V'
        let source = CGEventSource(stateID: .combinedSessionState)

        // Key down: Cmd + V
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true) {
            keyDown.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
        }

        // Key up: Cmd + V
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) {
            keyUp.flags = .maskCommand
            keyUp.post(tap: .cghidEventTap)
        }
    }
}

