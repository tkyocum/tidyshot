import AppKit
import Testing
@testable import TidyShot

/// The editor's tool segments carry one tool tip each, placed over the segments the toolbar draws.
@MainActor
struct EditorToolbarTests {
    @Test func everyToolSegmentHasItsToolTip() {
        let control = EditorWindowController.makeToolsControl(selected: .select)
        #expect(control.segmentCount == EditorTool.toolbarOrder.count)
        #expect(control.segmentToolTips == EditorTool.toolbarOrder.map(\.tooltip))
        for (index, tool) in EditorTool.toolbarOrder.enumerated() {
            #expect(control.image(forSegment: index)?.accessibilityDescription == tool.title)
        }
    }

    /// Equal widths make the toolbar draw the segments evenly, which the tip rects assume.
    @Test func everySegmentHasTheSameWidth() {
        let control = EditorWindowController.makeToolsControl(selected: .select)
        let widths = Set((0..<control.segmentCount).map { control.width(forSegment: $0) })
        #expect(widths.count == 1)
        #expect(widths.first ?? 0 > 0)
    }

    @Test func theControlSelectsOneToolAtATime() {
        let tool = EditorTool.toolbarOrder[EditorTool.toolbarOrder.count - 1]
        let control = EditorWindowController.makeToolsControl(selected: tool)
        #expect(control.trackingMode == .selectOne)
        #expect(control.selectedSegment == EditorTool.toolbarOrder.count - 1)
    }

    @Test func theControlHasAWidthToMeasure() {
        let control = EditorWindowController.makeToolsControl(selected: .select)
        #expect(control.fittingSize.width > CGFloat(EditorTool.toolbarOrder.count) * 20)
    }

    /// The window's real minimum, from a real editor with a long title: `minimumToolbarContentWidth()`
    /// measures the tools' control as the toolbar lays it out (35 pt a segment), which is wider than
    /// a fresh control's fitting width. The fourteen tools still fit the 90 % of a 1280 pt display
    /// an editor may open at (spec 2.12, Shared).
    @Test func measuredToolbarFitsASmallDisplay() {
        let controller = Self.makeEditor(title: "Screenshot 2026-10-22 at 23.47.12 of a window with a very long title.png")
        defer { controller.close() }
        // The installed control, not the fresh one minimumToolbarContentWidth() falls back to.
        let installed = controller.window?.toolbar?.items.first { $0.itemIdentifier == .tools }?.view
        #expect(installed is ToolSegmentedControl)
        let minimum = controller.minimumToolbarContentWidth()
        #expect(controller.window?.contentMinSize.width == minimum)
        let ninetyPercent = (1280 * EditorWindowGeometry.screenFraction).rounded(.down)
        #expect(ninetyPercent == 1152)
        #expect(minimum <= ninetyPercent)
    }

    private static func makeEditor(title: String) -> EditorWindowController {
        let context = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let model = EditorModel(recordID: UUID(), image: ScaledImage(image: context.makeImage()!, scale: 2),
                                renderer: FakeTileRenderer(), defaults: .standard)
        let actions = EditorActions(
            save: { _ in false }, saveAs: { _, _ in false },
            saveAsSuggestion: { EditorNaming.SaveAsSuggestion(fileName: "x.png", directory: nil) },
            copy: { _ in }, objectClipboard: EditorObjectClipboard(copy: { _ in }, paste: { nil }, canPaste: { false }),
            upload: { _, _ in .refused }, exportFailed: { _, _ in }, unusableBackgroundImage: { _ in })
        return EditorWindowController(model: model, actions: actions, title: title, representedURL: nil, cascadeFrom: nil)
    }

    /// What the editor opened with is what it stores back, the 4c defaults included.
    @Test func currentDefaultsCarryEveryEditorDefault() {
        let opened = EditorDefaults(strokeColor: RGBA(red: 0, green: 0.5, blue: 1, alpha: 1),
                                    redactColor: RGBA(red: 1, green: 1, blue: 1, alpha: 1),
                                    lineWidthPoints: 12, blurRadiusPoints: 20, blockPoints: 6,
                                    spotlightEllipse: true, counterDiameterPoints: 44)
        let context = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let model = EditorModel(recordID: UUID(), image: ScaledImage(image: context.makeImage()!, scale: 2),
                                renderer: FakeTileRenderer(), defaults: opened)
        #expect(model.spotlightEllipse)
        #expect(model.counterDiameterPoints == 44)
        #expect(model.currentDefaults == opened)
        model.spotlightEllipse = false
        model.counterDiameterPoints = 24
        #expect(model.currentDefaults.spotlightEllipse == false)
        #expect(model.currentDefaults.counterDiameterPoints == 24)
    }

    @Test func segmentRectsSplitTheBoundsEvenly() {
        let rects = ToolSegmentedControl.segmentRects(in: CGRect(x: 0, y: 0, width: 420, height: 36), count: 12)
        #expect(rects.count == 12)
        #expect(rects.first == CGRect(x: 0, y: 0, width: 35, height: 36))
        #expect(rects.last == CGRect(x: 385, y: 0, width: 35, height: 36))
        for (previous, next) in zip(rects, rects.dropFirst()) {
            #expect(previous.maxX == next.minX)
        }
    }

    @Test func segmentRectsAreEmptyWithoutSegmentsOrWidth() {
        #expect(ToolSegmentedControl.segmentRects(in: CGRect(x: 0, y: 0, width: 420, height: 36), count: 0).isEmpty)
        #expect(ToolSegmentedControl.segmentRects(in: .zero, count: 12).isEmpty)
    }
}
