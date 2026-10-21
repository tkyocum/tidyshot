import AppKit

/// All-in-One's toolbar: W and H fields, the aspect lock, a separator, then the actions (spec 2.9).
/// A subview of the selection view, so the area capture excludes it with the overlay window, and
/// the key, borderless overlay window can hold its text fields.
final class AllInOneToolbar: NSVisualEffectView, NSTextFieldDelegate {
    var onAction: ((AllInOneAction) -> Void)?
    /// Return in W gives (width, nil), in H (nil, height): whole points above 0.
    var onSize: ((_ width: Int?, _ height: Int?) -> Void)?
    var onToggleLock: (() -> Void)?
    /// Called after Return or Escape in a field, so the selection view takes focus back.
    var onFieldDone: (() -> Void)?

    private let widthField = AllInOneToolbar.makeField(accessibilityLabel: "Width")
    private let heightField = AllInOneToolbar.makeField(accessibilityLabel: "Height")
    private let lockButton: NSButton
    private var actionButtons: [AllInOneAction: NSButton] = [:]

    /// `timerSeconds` nil leaves the Timer button out.
    init(timerSeconds: Int?) {
        lockButton = Self.makeButton(symbolName: AllInOneLock.symbolName(locked: false),
                                     description: AllInOneLock.help)
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true

        widthField.delegate = self
        heightField.delegate = self
        widthField.nextKeyView = heightField
        heightField.nextKeyView = widthField

        lockButton.toolTip = AllInOneLock.help
        lockButton.target = self
        lockButton.action = #selector(toggleLock)

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        var views: [NSView] = [Self.makeLabel("W"), widthField, Self.makeLabel("H"), heightField, lockButton, separator]
        for action in AllInOneAction.allCases where action != .timer || timerSeconds != nil {
            let button = Self.makeButton(symbolName: action.symbolName, description: action.title)
            button.toolTip = action.help(timerSeconds: timerSeconds ?? 0)
            button.setAccessibilityLabel(action.title)
            button.target = self
            button.action = #selector(actionClicked(_:))
            actionButtons[action] = button
            views.append(button)
        }

        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 20),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Writes W and H (whole points) unless that field is being edited, the lock's symbol, and
    /// the Window button's enabled state.
    func update(size: CGSize, locked: Bool, windowEnabled: Bool) {
        actionButtons[.window]?.isEnabled = AllInOneAction.window.isEnabled(hasWindow: windowEnabled)
        lockButton.image = NSImage(systemSymbolName: AllInOneLock.symbolName(locked: locked),
                                   accessibilityDescription: AllInOneLock.help)
        for (field, side) in [(widthField, size.width), (heightField, size.height)] where field.currentEditor() == nil {
            field.stringValue = String(Int(side.rounded()))
        }
    }

    // MARK: Events

    /// A press on the background must not reach the selection view and start a new rect.
    override func mouseDown(with event: NSEvent) {}

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    @objc private func toggleLock() { onToggleLock?() }

    @objc private func actionClicked(_ sender: NSButton) {
        guard let action = actionButtons.first(where: { $0.value === sender })?.key else { return }
        onAction?(action)
    }

    // MARK: NSTextFieldDelegate

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            if let field = control as? NSTextField,
               let value = Int(field.stringValue.trimmingCharacters(in: .whitespaces)), value > 0 {
                if field === widthField {
                    onSize?(value, nil)
                } else if field === heightField {
                    onSize?(nil, value)
                }
            }
            onFieldDone?()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onFieldDone?()
            return true
        default:
            return false
        }
    }

    // MARK: Building

    private static func makeField(accessibilityLabel: String) -> NSTextField {
        let field = NSTextField()
        field.alignment = .right
        field.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        field.setAccessibilityLabel(accessibilityLabel)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 56).isActive = true
        return field
    }

    private static func makeLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.textColor = .secondaryLabelColor
        return label
    }

    /// A borderless 28 x 28 image button that never takes focus from the selection view.
    private static func makeButton(symbolName: String, description: String) -> NSButton {
        let button = NSButton()
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.refusesFirstResponder = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return button
    }
}
