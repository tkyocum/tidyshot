import SwiftUI

/// The options popover, `Tool options` (spec 2.6, Palette and options; spec 2.12, Options): line
/// width, blur radius, pixel block, and the spotlights' Shape and Dim. It stays one form: a row
/// that does not apply is disabled, never swapped out per tool. Each control applies live through
/// `EditorModel`, which commits a selected annotation under a coalescing key, so one slider drag
/// is one undo step. Only the slider for the effect in play is enabled: the selected blur or
/// pixelate, else the active Blur or Pixelate tool. A selected annotation of another kind does not
/// decide it, so with a rectangle selected the active effect tool's slider still works and sets
/// only the default. While the Highlighter is in play the width control edits the highlighter's
/// width; with a spotlight selected it sets only the default.
///
/// `Shape` (`Rectangle`, `Ellipse`) is enabled while Spotlight is the tool or a spotlight is
/// selected (`spotlightShapeApplies`); it sets the default for new spotlights and changes a
/// selected one. `Dim` (`30 %`, `50 %`, `70 %`) follows the same rule and also needs a spotlight in
/// the document (`spotlightDimApplies`); it shows the document's dim, 50 % before the first
/// spotlight.
struct ToolOptionsView: View {
    let model: EditorModel

    var body: some View {
        Form {
            Picker("Line width", selection: lineWidth) {
                ForEach(EditorPalette.lineWidthsPoints, id: \.self) { width in
                    Text("\(Int(width))").tag(width)
                }
            }
            .pickerStyle(.segmented)
            .help("Keys 1 to 6")
            LabeledContent("Blur radius") {
                HStack {
                    Slider(value: blurRadius, in: RedactionDefaults.blurRangePoints, step: 1)
                    readout(model.blurRadiusPoints)
                }
            }
            .disabled(effectTool != .blur)
            LabeledContent("Pixel block") {
                HStack {
                    Slider(value: block, in: RedactionDefaults.blockRangePoints, step: 1)
                    readout(model.blockPoints)
                }
            }
            .disabled(effectTool != .pixelate)
            Picker("Shape", selection: spotlightShape) {
                Text("Rectangle").tag(false)
                Text("Ellipse").tag(true)
            }
            .pickerStyle(.segmented)
            .disabled(!model.spotlightShapeApplies)
            Picker("Dim", selection: spotlightDim) {
                ForEach(EditorPalette.spotlightDims, id: \.self) { dim in
                    Text("\(Int((dim * 100).rounded())) %").tag(dim)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!model.spotlightDimApplies)
        }
        .formStyle(.columns)
        .padding(12)
        .frame(width: 300)
    }

    private func readout(_ points: CGFloat) -> some View {
        Text("\(Int(points)) pt")
            .monospacedDigit()
            .frame(width: 40, alignment: .trailing)
    }

    /// The effect the sliders act on: the selected annotation's kind, else the active tool's.
    private var effectTool: EditorTool? {
        if let id = model.selection, let annotation = model.document.annotation(id: id) {
            switch annotation {
            case .blur: return .blur
            case .pixelate: return .pixelate
            default: break
            }
        }
        return model.tool == .blur || model.tool == .pixelate ? model.tool : nil
    }

    private var lineWidth: Binding<CGFloat> {
        Binding(get: { model.activeLineWidthPoints }, set: { model.applyLineWidth(points: $0) })
    }

    private var blurRadius: Binding<CGFloat> {
        Binding(get: { model.blurRadiusPoints }, set: { model.applyEffectParameter(.blurRadius, points: $0) })
    }

    private var block: Binding<CGFloat> {
        Binding(get: { model.blockPoints }, set: { model.applyEffectParameter(.block, points: $0) })
    }

    private var spotlightShape: Binding<Bool> {
        Binding(get: { model.activeSpotlightEllipse }, set: { model.applySpotlightShape(isEllipse: $0) })
    }

    private var spotlightDim: Binding<Double> {
        Binding(get: { model.document.effectiveSpotlightDim }, set: { model.applySpotlightDim($0) })
    }
}
