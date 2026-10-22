import AppKit
import Testing
@testable import TidyShot

/// The editor's tool segments carry one tool tip each, because AppKit's toolbar item group shows none.
@MainActor
struct EditorToolbarTests {
    @Test func everyToolSegmentHasItsToolTip() {
        let control = EditorWindowController.makeToolsControl(selected: .select)
        #expect(control.segmentCount == EditorTool.toolbarOrder.count)
        for (index, tool) in EditorTool.toolbarOrder.enumerated() {
            #expect(control.toolTip(forSegment: index) == tool.tooltip)
            #expect(control.image(forSegment: index)?.accessibilityDescription == tool.title)
        }
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
}
