import AppKit

/// The annotation editor's window. The SwiftUI main menu of an LSUIElement app is never drawn, so
/// editor shortcuts are looked up here, in the pure `EditorShortcut` table. The key window sees a
/// key equivalent before the main menu, so a matched chord is handled exactly once.
final class EditorWindow: NSWindow {
    /// Set by EditorWindowController. While its `isEditingText`, the clipboard and undo chords, and
    /// ⌘X (with Task 5, ⌘V too), go to the text view.
    weak var canvasView: CanvasView?

    /// `NSApp.sendAction` does not consult NSUserInterfaceValidations, so a matched shortcut is
    /// validated against the target that would receive it first: a refusal beeps and consumes the
    /// event. While text is typed, the chords the table leaves alone (`TextEditingChord`) are sent to
    /// the text view the same way. Anything else (⌘Q, ⌘,, or ⌘X when nothing is typed) goes on to
    /// super and the main menu.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Behind the unsaved-changes sheet, editor shortcuts do nothing.
        guard attachedSheet == nil, event.type == .keyDown, let characters = event.charactersIgnoringModifiers else {
            return super.performKeyEquivalent(with: event)
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = flags.contains(.command)
        let shift = flags.contains(.shift)
        let option = flags.contains(.option)
        let control = flags.contains(.control)
        let isEditingText = canvasView?.isEditingText ?? false
        // charactersIgnoringModifiers keeps Shift ("S" for ⇧⌘S), so it is lower-cased here and
        // Shift travels as its own flag.
        if let shortcut = EditorShortcut.match(characters: characters.lowercased(), command: command, shift: shift,
                                               option: option, control: control, isEditingText: isEditingText) {
            return send(NSSelectorFromString(shortcut.selectorName))
        }
        if isEditingText, let name = TextEditingChord.selectorName(characters: characters, command: command, shift: shift,
                                                                   option: option, control: control) {
            return send(NSSelectorFromString(name))
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Sends `action` up the responder chain after its first target validates it; a refusal beeps.
    /// Either way the event is consumed, so a main-menu item with the same key never fires as well.
    private func send(_ action: Selector) -> Bool {
        guard let target = NSApp.target(forAction: action, to: nil, from: self),
              (target as? NSUserInterfaceValidations)?.validateUserInterfaceItem(ShortcutItem(action: action)) ?? true else {
            NSSound.beep()
            return true
        }
        NSApp.sendAction(action, to: target, from: self)
        return true
    }
}

/// What a validator sees for a keyboard shortcut: its action, and no tag.
final class ShortcutItem: NSObject, NSValidatedUserInterfaceItem {
    let action: Selector?
    let tag = 0

    init(action: Selector) {
        self.action = action
    }
}
