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

    /// The window's real minimum uses the control's measured width, not 36 pt a segment. Measured
    /// as `minimumToolbarContentWidth()` measures it, with a long title, the fourteen tools still
    /// fit the 90 % of a 1280 pt display an editor may open at (spec 2.12, Shared).
    @Test func measuredToolbarFitsASmallDisplay() {
        let toolsWidth = EditorWindowController.makeToolsControl(selected: .select).fittingSize.width
        let width = EditorWindowGeometry.toolbarWidth(
            windowButtonsMaxX: EditorWindowGeometry.ToolbarMetrics.windowButtons, titleWidth: 230, toolSegments: 0,
            buttons: 5, prominentButtons: 1, viewWidths: [84, toolsWidth], fixedSpaces: 1)
        let ninetyPercent = (1280 * EditorWindowGeometry.screenFraction).rounded(.down)
        #expect(ninetyPercent == 1152)
        #expect(EditorWindowGeometry.minimumContentWidth(toolbarWidth: width) <= ninetyPercent)
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
