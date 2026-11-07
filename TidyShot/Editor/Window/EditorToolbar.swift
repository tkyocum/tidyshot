import AppKit
import Observation
import SwiftUI

extension NSToolbarItem.Identifier {
    static let tools = NSToolbarItem.Identifier("editor.tools")
    static let color = NSToolbarItem.Identifier("editor.color")
    static let toolOptions = NSToolbarItem.Identifier("editor.toolOptions")
    static let background = NSToolbarItem.Identifier("editor.background")
    static let zoom = NSToolbarItem.Identifier("editor.zoom")
    static let copyImage = NSToolbarItem.Identifier("editor.copyImage")
    static let save = NSToolbarItem.Identifier("editor.save")
    static let upload = NSToolbarItem.Identifier("editor.upload")
}

extension EditorModel {
    /// This editor's colours and sizes, in the shape AppSettings stores.
    var currentDefaults: EditorDefaults {
        EditorDefaults(strokeColor: strokeColor, redactColor: redactColor, lineWidthPoints: lineWidthPoints,
                       blurRadiusPoints: blurRadiusPoints, blockPoints: blockPoints,
                       spotlightEllipse: spotlightEllipse, counterDiameterPoints: counterDiameterPoints)
    }
}

/// The editor toolbar (spec 2.6, Window): `NSToolbar(identifier: "AnnotationEditor")`, icon only,
/// not customisable. Copy, Save and Upload are plain buttons with no menus, and the window is never
/// narrower than the toolbar (`minimumToolbarContentWidth()`), so nothing overflows. Its state
/// follows the model through Observation, so letter keys, digit keys and pinch zoom show here
/// without the canvas knowing about the toolbar. Liquid Glass comes free: no custom backgrounds.
extension EditorWindowController: NSToolbarDelegate, NSToolbarItemValidation {
    private static let itemIdentifiers: [NSToolbarItem.Identifier] = [
        .tools, .space, .color, .toolOptions, .background, .flexibleSpace, .zoom, .copyImage, .save, .upload,
    ]
    private static let zoomPopUpWidth: CGFloat = 84
    /// Each tool segment's width before the toolbar's padding; the toolbar draws them 35 pt apart.
    private static let toolSegmentWidth: CGFloat = 28

    /// The narrowest content width that shows every item of `itemIdentifiers`: the window buttons
    /// and the title measured from the window, the zoom pop-up at its fixed width, the tools'
    /// segmented control at its fitting width, and the items AppKit draws itself (Colour, Options,
    /// Background, Copy and Save; the prominent Upload; the fixed space) from
    /// `EditorWindowGeometry.ToolbarMetrics`.
    func minimumToolbarContentWidth() -> CGFloat {
        guard let window else { return EditorWindowGeometry.minimumContentSize.width }
        let measured = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
            .compactMap { window.standardWindowButton($0)?.frame.maxX }.max() ?? 0
        let windowButtonsMaxX = measured > 0 ? measured : EditorWindowGeometry.ToolbarMetrics.windowButtons
        let titleWidth = (window.title as NSString).size(withAttributes: [.font: NSFont.titleBarFont(ofSize: 0)]).width
        // The tools are a segmented control of our own, so their width is measured, not estimated.
        let toolsWidth = (toolbarItem(.tools)?.view ?? Self.makeToolsControl(selected: model.tool)).fittingSize.width
        let width = EditorWindowGeometry.toolbarWidth(
            windowButtonsMaxX: windowButtonsMaxX, titleWidth: titleWidth, toolSegments: 0,
            buttons: [NSToolbarItem.Identifier.color, .toolOptions, .background, .copyImage, .save].count,
            prominentButtons: 1,
            viewWidths: [Self.zoomPopUpWidth, toolsWidth],
            fixedSpaces: Self.itemIdentifiers.filter { $0 == .space }.count)
        return EditorWindowGeometry.minimumContentWidth(toolbarWidth: width)
    }

    /// Called once from `init`, after `super.init(window:)` and before the window is placed.
    func installToolbar() {
        let toolbar = NSToolbar(identifier: "AnnotationEditor")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window?.toolbar = toolbar
        observeToolbarState()
    }

    // MARK: NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.itemIdentifiers
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.itemIdentifiers
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case .tools:
            return makeToolsItem()
        case .color:
            return makeButtonItem(.color, label: "Colour", toolTip: "Colour",
                                  image: swatchImage(model.activeColor), action: #selector(showColorPalette(_:)))
        case .toolOptions:
            return makeButtonItem(.toolOptions, label: "Options", toolTip: "Tool options",
                                  image: symbol("slider.horizontal.3", "Options"), action: #selector(showToolOptions(_:)))
        case .background:
            return makeButtonItem(.background, label: "Background", toolTip: "Background",
                                  image: symbol("rectangle.inset.filled", "Background"),
                                  action: #selector(showBackgroundOptions(_:)))
        case .zoom:
            return makeZoomItem()
        case .copyImage:
            return makeButtonItem(.copyImage, label: "Copy", toolTip: "Copy the image (⌘C)",
                                  image: symbol("doc.on.doc", "Copy"), action: #selector(copyImage(_:)))
        case .save:
            return makeButtonItem(.save, label: "Save", toolTip: "Save (⌘S)",
                                  image: symbol("square.and.arrow.down", "Save"), action: #selector(saveDocument(_:)))
        case .upload:
            let item = makeButtonItem(.upload, label: "Upload", toolTip: "Upload and copy the link (⌘U)",
                                      image: symbol("icloud.and.arrow.up", "Upload"), action: #selector(uploadDocument(_:)))
            item.style = .prominent
            return item
        default:
            return nil
        }
    }

    // MARK: Validation

    /// Copy, Save and Upload follow the same answer as their shortcuts (Task 13's gate). Colour
    /// follows `EditorModel.colorApplies`: off for the Spotlight tool with no coloured selection and
    /// with a spotlight selected. The rest are always enabled.
    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        switch item.itemIdentifier {
        case .copyImage, .save, .upload: validateUserInterfaceItem(item)
        case .color: model.colorApplies
        default: true
        }
    }

    // MARK: Following the model

    /// Re-registers on every change, as `StatusMenuController.updateIcon()` does: Observation calls
    /// `onChange` once, before the change, so the update runs in a scheduled task. `previous` is the
    /// model's defaults at the last registration, so only what this editor changed is stored and two
    /// open editors do not overwrite each other's choices.
    func observeToolbarState(previous: EditorDefaults? = nil) {
        let defaults = model.currentDefaults
        if let previous { storeChangedDefaults(from: previous, to: defaults) }
        let state = withObservationTracking {
            _ = model.currentDefaults
            return (tool: model.tool, color: model.activeColor,
                    percent: model.transform.percent(captureScale: model.scale))
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeToolbarState(previous: defaults) }
        }
        reflectTool(state.tool)
        reflectColor(state.color)
        reflectZoom(percent: state.percent)
    }

    /// Keeps the segments in step when a letter key changed the tool. Setting `selectedSegment`
    /// does not send the action, so there is no loop.
    func reflectTool(_ tool: EditorTool) {
        guard let control = toolbarItem(.tools)?.view as? NSSegmentedControl,
              let index = EditorTool.toolbarOrder.firstIndex(of: tool), control.selectedSegment != index else { return }
        control.selectedSegment = index
    }

    /// A new swatch image only when the colour changed: one observation covers the tool, the colour
    /// and the zoom, so this also runs on every pan and pinch event.
    private func reflectColor(_ color: RGBA) {
        guard color != reflectedColor else { return }
        reflectedColor = color
        toolbarItem(.color)?.image = swatchImage(color)
    }

    /// A pull-down shows its first item's title, which `setTitle(_:)` sets.
    private func reflectZoom(percent: Int) {
        guard percent != reflectedZoomPercent else { return }
        reflectedZoomPercent = percent
        (toolbarItem(.zoom)?.view as? NSPopUpButton)?.setTitle("\(percent) %")
    }

    private func storeChangedDefaults(from old: EditorDefaults, to new: EditorDefaults) {
        let settings = AppSettings.shared
        if new.strokeColor != old.strokeColor { settings.editorStrokeColor = new.strokeColor }
        if new.redactColor != old.redactColor { settings.editorRedactColor = new.redactColor }
        if new.lineWidthPoints != old.lineWidthPoints { settings.editorLineWidthPoints = Double(new.lineWidthPoints) }
        if new.blurRadiusPoints != old.blurRadiusPoints { settings.editorBlurRadiusPoints = Double(new.blurRadiusPoints) }
        if new.blockPoints != old.blockPoints { settings.editorPixelBlockPoints = Double(new.blockPoints) }
        if new.spotlightEllipse != old.spotlightEllipse { settings.editorSpotlightEllipse = new.spotlightEllipse }
        if new.counterDiameterPoints != old.counterDiameterPoints {
            settings.editorCounterDiameterPoints = Double(new.counterDiameterPoints)
        }
    }

    // MARK: Actions

    /// The segments send this.
    @objc func selectToolFromToolbar(_ sender: Any?) {
        guard let control = sender as? NSSegmentedControl,
              EditorTool.toolbarOrder.indices.contains(control.selectedSegment) else { return }
        model.tool = EditorTool.toolbarOrder[control.selectedSegment]
    }

    /// The menu form's items send this, with the tool's index as the tag.
    @objc func selectToolFromMenu(_ sender: NSMenuItem) {
        guard EditorTool.toolbarOrder.indices.contains(sender.tag) else { return }
        model.tool = EditorTool.toolbarOrder[sender.tag]
    }

    @objc func showColorPalette(_ sender: Any?) {
        colorPopover = showPopover(ColorPaletteView(model: model), from: .color)
    }

    @objc func showToolOptions(_ sender: Any?) {
        optionsPopover = showPopover(ToolOptionsView(model: model), from: .toolOptions)
    }

    @objc func showBackgroundOptions(_ sender: Any?) {
        let view = BackgroundPopoverView(model: model) { [weak self] fileName in
            self?.reportUnusableBackgroundImage(named: fileName)
        }
        backgroundPopover = showPopover(view, from: .background)
    }

    /// 50 %, 200 % and 400 % from the zoom pop-up: `tag` percent of natural size, around the
    /// view centre, through `CanvasView` like ⌘=, so the canvas stops refitting on resize and
    /// redraws at once.
    @objc func zoomToPercent(_ sender: NSMenuItem) {
        canvasView.commitTextEditing()
        canvasView.zoom(to: CGFloat(sender.tag) / 100 / model.scale)
    }

    /// One popover at a time. `.transient` closes it on a click elsewhere; values apply live, so
    /// there is nothing to confirm. `show(relativeTo:)` anchors to the item, or to the overflow
    /// chevron when the item has moved into the overflow menu. The item is looked up by identifier
    /// because the overflow menu sends an `NSMenuItem`.
    private func showPopover(_ content: some View, from identifier: NSToolbarItem.Identifier) -> NSPopover? {
        colorPopover?.close()
        optionsPopover?.close()
        backgroundPopover?.close()
        guard let item = toolbarItem(identifier) else { return nil }
        let host = NSHostingController(rootView: content)
        host.sizingOptions = .preferredContentSize
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = host
        popover.show(relativeTo: item)
        return popover
    }

    // MARK: Items

    /// A segmented control of our own rather than an `NSToolbarItemGroup`: the group draws its
    /// segments in a private picker view and shows no sub-item tool tips, so hovering a tool told
    /// the user nothing. The window is never narrower than the toolbar, so the item never collapses
    /// into its menu form.
    private func makeToolsItem() -> NSToolbarItem {
        let control = Self.makeToolsControl(selected: model.tool)
        control.target = self
        control.action = #selector(selectToolFromToolbar(_:))
        let item = NSToolbarItem(itemIdentifier: .tools)
        item.label = "Tools"
        item.view = control
        let form = NSMenuItem(title: "Tools", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Tools")
        for (index, tool) in EditorTool.toolbarOrder.enumerated() {
            let entry = NSMenuItem(title: tool.title, action: #selector(selectToolFromMenu(_:)), keyEquivalent: "")
            entry.target = self
            entry.tag = index
            menu.addItem(entry)
        }
        form.submenu = menu
        item.menuFormRepresentation = form
        return item
    }

    /// One segment per tool in `EditorTool.toolbarOrder`, each with its symbol, accessibility
    /// title and tool tip ("Redact (D)"), all `toolSegmentWidth` wide so the tips line up.
    static func makeToolsControl(selected: EditorTool) -> ToolSegmentedControl {
        let tools = EditorTool.toolbarOrder
        let control = ToolSegmentedControl()
        control.trackingMode = .selectOne
        control.segmentCount = tools.count
        for (index, tool) in tools.enumerated() {
            control.setImage(NSImage(systemSymbolName: tool.symbolName, accessibilityDescription: tool.title), forSegment: index)
            control.setWidth(Self.toolSegmentWidth, forSegment: index)
        }
        control.segmentToolTips = tools.map(\.tooltip)
        control.selectedSegment = tools.firstIndex(of: selected) ?? 0
        control.sizeToFit()
        return control
    }

    private func makeButtonItem(_ identifier: NSToolbarItem.Identifier, label: String, toolTip: String,
                                image: NSImage?, action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.toolTip = toolTip
        item.image = image
        item.target = self
        item.action = action
        return item
    }

    private func makeZoomItem() -> NSToolbarItem {
        let popUp = NSPopUpButton(frame: .zero, pullsDown: true)
        popUp.menu = zoomMenu(withTitleItem: true)
        // The title changes; the width does not.
        popUp.widthAnchor.constraint(equalToConstant: Self.zoomPopUpWidth).isActive = true
        let item = NSToolbarItem(itemIdentifier: .zoom)
        item.label = "Zoom"
        item.toolTip = "Zoom"
        item.view = popUp
        let form = NSMenuItem(title: "Zoom", action: nil, keyEquivalent: "")
        form.submenu = zoomMenu(withTitleItem: false)
        item.menuFormRepresentation = form
        return item
    }

    /// Fit, 50 %, 100 %, 200 % and 400 %. A pull-down's first item is its title, so the pop-up
    /// adds one showing the current percent. Zoom is always available.
    private func zoomMenu(withTitleItem: Bool) -> NSMenu {
        let menu = NSMenu(title: "Zoom")
        menu.autoenablesItems = false
        if withTitleItem {
            menu.addItem(withTitle: "\(model.transform.percent(captureScale: model.scale)) %", action: nil, keyEquivalent: "")
        }
        for (title, selector, tag) in [("Fit", #selector(zoomToFit(_:)), 0),
                                       ("50 %", #selector(zoomToPercent(_:)), 50),
                                       ("100 %", #selector(zoomToActualSize(_:)), 100),
                                       ("200 %", #selector(zoomToPercent(_:)), 200),
                                       ("400 %", #selector(zoomToPercent(_:)), 400)] {
            let entry = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            entry.target = self
            entry.tag = tag
            menu.addItem(entry)
        }
        return menu
    }

    // MARK: Helpers

    private func toolbarItem(_ identifier: NSToolbarItem.Identifier) -> NSToolbarItem? {
        window?.toolbar?.items.first { $0.itemIdentifier == identifier }
    }

    private func symbol(_ name: String, _ description: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: description)
    }

    /// The current colour as a filled circle with a hairline edge, so white shows on a light toolbar.
    private func swatchImage(_ color: RGBA) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            NSColor(cgColor: color.cgColor)?.setFill()
            circle.fill()
            NSColor.separatorColor.setStroke()
            circle.lineWidth = 1
            circle.stroke()
            return true
        }
        image.accessibilityDescription = "Colour"
        return image
    }
}
