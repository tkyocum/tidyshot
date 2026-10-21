import AppKit

/// The annotation editor's window. The SwiftUI main menu of an LSUIElement app is never drawn, so
/// editor shortcuts are looked up here, in the pure `EditorShortcut` table. The key window sees a
/// key equivalent before the main menu, so a matched chord is handled exactly once.
final class EditorWindow: NSWindow {
    /// Set by EditorWindowController. Its `isEditingText` (4b) lets the clipboard and undo chords
    /// through to the text view.
    weak var canvasView: CanvasView?

    /// `NSApp.sendAction` does not consult NSUserInterfaceValidations, so a matched shortcut is
    /// validated against the target that would receive it first: a refusal beeps and consumes the
    /// event. Anything the table does not match (⌘X, ⌘Q, ⌘,) goes on to super and the main menu.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Behind the unsaved-changes sheet, editor shortcuts do nothing.
        guard attachedSheet == nil, event.type == .keyDown, let characters = event.charactersIgnoringModifiers else {
            return super.performKeyEquivalent(with: event)
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // charactersIgnoringModifiers keeps Shift ("S" for ⇧⌘S), so it is lower-cased here and
        // Shift travels as its own flag.
        guard let shortcut = EditorShortcut.match(characters: characters.lowercased(),
                                                  command: flags.contains(.command), shift: flags.contains(.shift),
                                                  option: flags.contains(.option), control: flags.contains(.control),
                                                  isEditingText: canvasView?.isEditingText ?? false) else {
            return super.performKeyEquivalent(with: event)
        }
        let action = NSSelectorFromString(shortcut.selectorName)
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
