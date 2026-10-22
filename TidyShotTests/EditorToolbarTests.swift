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
