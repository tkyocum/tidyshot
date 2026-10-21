import AppKit

/// A pin's content: a layer showing the image with a hairline border, the pin's keys, Option-scroll
/// opacity and its context menu. It holds no state of its own; `PinController` sets the closures.
final class PinView: NSView {
    var onCommand: (PinCommand) -> Void = { _ in }
    var onOpacitySteps: (Int) -> Void = { _ in }
    /// A preset from the Opacity submenu.
    var onOpacity: (Double) -> Void = { _ in }
    var onSaveAs: () -> Void = {}
    var onAnnotate: () -> Void = {}
    var onLock: () -> Void = {}
    /// The pin's current opacity, for the check mark in the Opacity submenu.
    var menuState: () -> Double = { 1.0 }
    /// Option-scroll that has not yet made a whole step.
    private var scrollRemainder: CGFloat = 0

    /// Lock turns the border off.
    var showsBorder = true {
        didSet { updateBorder() }
    }

    init(image: CGImage) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.contents = image
        layer?.contentsGravity = .resize
        layer?.minificationFilter = .trilinear
        layer?.magnificationFilter = .linear
        layer?.borderColor = NSColor(white: 0.5, alpha: 0.6).cgColor
        updateBorder()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Window dragging can take the click without making a non-activating panel key, and the
    /// arrows, Escape and the Command keys need it key.
    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        super.mouseDown(with: event)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateBorder()
    }

    /// One device pixel wide.
    private func updateBorder() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        layer?.borderWidth = showsBorder ? 1 / scale : 0
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateBorder()
    }

    // MARK: Keys

    private func command(for event: NSEvent) -> PinCommand? {
        let flags = event.modifierFlags
        return PinKeys.command(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers,
                               command: flags.contains(.command), shift: flags.contains(.shift),
                               option: flags.contains(.option), control: flags.contains(.control))
    }

    override func keyDown(with event: NSEvent) {
        if let command = command(for: event) {
            onCommand(command)
        } else {
            super.keyDown(with: event)
        }
    }

    /// The app has no main menu items for the command keys, so they arrive here.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let command = command(for: event) else { return false }
        onCommand(command)
        return true
    }

    // MARK: Opacity

    /// Option-scroll changes the opacity: one step per 8 points of a trackpad, per 1 of a wheel.
    /// Scrolling up is more opaque.
    override func scrollWheel(with event: NSEvent) {
        guard event.modifierFlags.contains(.option) else {
            nextResponder?.scrollWheel(with: event)
            return
        }
        let perStep: CGFloat = event.hasPreciseScrollingDeltas ? 8 : 1
        scrollRemainder += event.scrollingDeltaY
        let steps = Int((scrollRemainder / perStep).rounded(.towardZero))
        if steps != 0 {
            scrollRemainder -= CGFloat(steps) * perStep
            onOpacitySteps(steps)
        }
        if event.phase == .ended || event.momentumPhase == .ended {
            scrollRemainder = 0
        }
    }

    // MARK: Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(item("Copy Image", #selector(copyImage)))
        menu.addItem(item("Save As…", #selector(saveAs)))
        menu.addItem(item("Annotate", #selector(annotate)))

        let opacity = NSMenuItem(title: "Opacity", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Opacity")
        let current = menuState()
        for preset in PinOpacity.presets {
            let presetItem = item(PinOpacity.title(for: preset), #selector(setOpacity(_:)))
            presetItem.representedObject = preset
            presetItem.state = PinOpacity.matches(preset, current) ? .on : .off
            submenu.addItem(presetItem)
        }
        opacity.submenu = submenu
        menu.addItem(opacity)

        menu.addItem(item("Actual Size", #selector(actualSize)))
        menu.addItem(item("Lock", #selector(lock)))
        menu.addItem(.separator())
        menu.addItem(item("Close", #selector(closePin)))
        return menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        menuItem.target = self
        return menuItem
    }

    @objc private func copyImage() { onCommand(.copyImage) }
    @objc private func saveAs() { onSaveAs() }
    @objc private func annotate() { onAnnotate() }
    @objc private func actualSize() { onCommand(.actualSize) }
    @objc private func lock() { onLock() }
    @objc private func closePin() { onCommand(.close) }

    @objc private func setOpacity(_ sender: NSMenuItem) {
        guard let preset = sender.representedObject as? Double else { return }
        onOpacity(preset)
    }
}
