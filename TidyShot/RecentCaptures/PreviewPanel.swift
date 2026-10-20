import AppKit

/// The full-size preview beside the Recent Captures submenu while a thumbnail is hovered. It is
/// non-activating and at `.popUpMenu`, the menus' own level, so ordering it front puts it above
/// the open menu without taking the menu's tracking or activating the app. It ignores the mouse,
/// so it never takes a hover or a click meant for the menu.
final class PreviewPanel: NSPanel {
    private let imageView = NSImageView()

    init() {
        super.init(contentRect: CGRect(x: 0, y: 0, width: 200, height: 150),
                   styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        // Not a floating panel: `isFloatingPanel = true` would put the level back to `.floating`,
        // below the menu.
        level = .popUpMenu
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none

        let background = NSVisualEffectView()
        background.material = .menu
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        background.layer?.masksToBounds = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 6),
            imageView.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -6),
            imageView.topAnchor.constraint(equalTo: background.topAnchor, constant: 6),
            imageView.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -6),
        ])
        contentView = background
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Shows `image` in `frame` (screen coordinates, from `PreviewPlacement`).
    func show(_ image: NSImage, frame: CGRect) {
        imageView.image = image
        setFrame(frame, display: true)
        orderFrontRegardless()
    }

    func hide() {
        orderOut(nil)
        imageView.image = nil
    }
}
