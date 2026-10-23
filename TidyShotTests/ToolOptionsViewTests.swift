import AppKit
import SwiftUI
import Testing
@testable import TidyShot

/// The options popover keeps one line per row in every state. Before 4c's fix, a spotlight made
/// the form re-lay out and `Line width` wrapped one letter per line, which made the popover tall.
@MainActor
struct ToolOptionsViewTests {
    private static func makeModel() -> EditorModel {
        let context = CGContext(data: nil, width: 400, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return EditorModel(recordID: UUID(), image: ScaledImage(image: context.makeImage()!, scale: 2),
                           renderer: FakeTileRenderer(), defaults: .standard)
    }

    /// The hosted view at the size it asks for.
    private static func hosted(_ model: EditorModel) -> NSHostingView<ToolOptionsView> {
        let view = NSHostingView(rootView: ToolOptionsView(model: model))
        view.frame = CGRect(origin: .zero, size: view.fittingSize)
        view.layoutSubtreeIfNeeded()
        return view
    }

    /// Six rows of controls, each one line high, with the padding: comfortably under this.
    private static let maximumHeight: CGFloat = 260

    @Test(arguments: [EditorTool.select, .pencil, .blur, .pixelate, .highlighter, .spotlight, .counter])
    func everyToolKeepsOneLinePerRow(tool: EditorTool) {
        let model = Self.makeModel()
        model.tool = tool
        let view = Self.hosted(model)
        #expect(view.frame.width == ToolOptionsView.width)
        #expect(view.frame.height <= Self.maximumHeight)
    }

    /// The popover is at least as wide as its widest row wants: the widest label, the grid's
    /// spacing, the six line-width segments and the padding. Below that, the old form squeezed the
    /// label (truncated offscreen, one letter per line in the real popover).
    @Test func thePopoverIsWideEnoughForItsWidestRow() {
        func idealWidth(_ view: some View) -> CGFloat { NSHostingView(rootView: view.fixedSize()).fittingSize.width }
        let widestLabel = ["Line width", "Blur radius", "Pixel block", "Shape", "Dim", "Size"].map { idealWidth(Text($0)) }.max() ?? 0
        let lineWidths = idealWidth(Picker("Line width", selection: .constant(CGFloat(4))) {
            ForEach(EditorPalette.lineWidthsPoints, id: \.self) { Text("\(Int($0))").tag($0) }
        }.pickerStyle(.segmented).labelsHidden())
        #expect(widestLabel > 0 && lineWidths > 0)
        #expect(widestLabel + 10 + lineWidths + 2 * 12 <= ToolOptionsView.width)
    }

    /// The reported case: a spotlight drawn and selected, with the Dim row live.
    @Test func aSelectedSpotlightKeepsOneLinePerRow() {
        let model = Self.makeModel()
        model.tool = .spotlight
        let spotlight = Annotation.spotlight(SpotlightShape(id: UUID(), rect: CGRect(x: 40, y: 40, width: 200, height: 120),
                                                            isEllipse: true))
        model.commit(model.document.appending(spotlight), actionName: "Add Spotlight")
        model.selection = spotlight.id
        #expect(model.spotlightDimApplies)
        model.applySpotlightDim(0.7)
        let view = Self.hosted(model)
        #expect(view.frame.width == ToolOptionsView.width)
        #expect(view.frame.height <= Self.maximumHeight)
    }
}
