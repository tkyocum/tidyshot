import AppKit

/// Covers one display's desktop icons and widgets with its wallpaper (spec 2.10). It sits just
/// above the widgets and below every normal window, on every Space. It never becomes key or main
/// and never activates TidyShot; clicks land on it and do nothing, so hidden icons cannot be
/// opened or dragged.
final class DesktopCoverPanel: OverlayPanel {
    /// Above Finder's icons (`desktopIconWindow`), the `underbelly` window (+1) and the widgets (+2).
    static let level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 3)

    private let coverView = CoverView()

    init(frame: CGRect) {
        // Not floating: that would lift it to `.floating`, above every normal window.
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], floating: false, level: Self.level,
                   collectionBehavior: [.canJoinAllSpaces, .stationary, .ignoresCycle], hasShadow: false, isOpaque: true)
        contentView = coverView
    }

    /// Shows `wallpaper`, stretched to the frame.
    func setWallpaper(_ wallpaper: CGImage) {
        coverView.layer?.contents = wallpaper
    }
}

/// Shows the wallpaper and swallows every click, so nothing reaches the desktop behind it.
private final class CoverView: NSView {
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.contentsGravity = .resize
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func rightMouseUp(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
    override func otherMouseUp(with event: NSEvent) {}
    override func menu(for event: NSEvent) -> NSMenu? { nil }
}
