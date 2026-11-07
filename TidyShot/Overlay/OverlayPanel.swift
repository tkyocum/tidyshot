import AppKit

/// The borderless window the overlays share: the self-timer badge, the pins, the recording bar,
/// the webcam bubble, the click rings, the desktop covers, the menu preview, the scrolling
/// capture's panel and the Quick Access cards. Each is on every Space, never hidden when TidyShot
/// deactivates, kept when closed, and never main; the subclass picks the level, the collection
/// behaviour, the shadow, the animation and whether clicks pass through. `isFloatingPanel` resets
/// `level` to `.floating`, so it is set first; a panel that sits below `.floating` (a desktop
/// cover) or above a menu (the preview) passes `floating: false`.
class OverlayPanel: NSPanel {
    init(contentRect: CGRect, styleMask: NSWindow.StyleMask, floating: Bool = true, level: NSWindow.Level,
         collectionBehavior: NSWindow.CollectionBehavior, hasShadow: Bool,
         animationBehavior: NSWindow.AnimationBehavior = .none, ignoresMouseEvents: Bool = false,
         isOpaque: Bool = false, defer: Bool = false) {
        super.init(contentRect: contentRect, styleMask: styleMask, backing: .buffered, defer: `defer`)
        isFloatingPanel = floating
        self.level = level
        hidesOnDeactivate = false
        self.collectionBehavior = collectionBehavior
        self.isOpaque = isOpaque
        if !isOpaque { backgroundColor = .clear }
        self.hasShadow = hasShadow
        self.ignoresMouseEvents = ignoresMouseEvents
        self.animationBehavior = animationBehavior
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
