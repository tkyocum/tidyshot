import SwiftUI

/// The options popover, `Tool options` (spec 2.6, Palette and options; spec 2.12, Options): line
/// width, blur radius, pixel block, the spotlights' Shape and Dim, and the counters' Size. It stays
/// one form: a row that does not apply is disabled, never swapped out per tool. Each control
/// applies live through `EditorModel`, which commits a selected annotation under a coalescing key,
/// so one slider drag is one undo step. Only the slider for the effect in play is enabled: the
/// selected blur or pixelate, else the active Blur or Pixelate tool. A selected annotation of
/// another kind does not decide it, so with a rectangle selected the active effect tool's slider
/// still works and sets only the default. While the Highlighter is in play the width control edits
/// the highlighter's width; with a spotlight or a counter selected it sets only the default.
///
/// `Shape` (`Rectangle`, `Ellipse`) is enabled while Spotlight is the tool or a spotlight is
/// selected (`spotlightShapeApplies`); it sets the default for new spotlights and changes a
/// selected one. `Dim` (`30 %`, `50 %`, `70 %`) follows the same rule and also needs a spotlight in
/// the document (`spotlightDimApplies`); it shows the document's dim, 50 % before the first
/// spotlight. `Size` (`Small`, `Medium`, `Large`: 24, 32 and 44 pt) is enabled while Counter is the
/// tool or a counter is selected (`counterSizeApplies`); it sets the default for new counters and
/// resizes a selected one about its centre.
struct ToolOptionsView: View {
    /// The Size row's labels, one per stop of `EditorPalette.counterDiametersPoints`.
    private static let counterSizeLabels = ["Small", "Medium", "Large"]

    let model: EditorModel

    /// The popover's width. A `Form` in `.columns` style gave the label column only what the
    /// six line-width segments left over, so `Line width` wrapped one letter per line once a state
    /// change re-laid the form out. A grid with labels that never wrap, at this width, fits every row.
    static let width: CGFloat = 340

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
            row("Line width") {
                Picker("Line width", selection: lineWidth) {
                    ForEach(EditorPalette.lineWidthsPoints, id: \.self) { width in
                        Text("\(Int(width))").tag(width)
                    }
                }
                .help("Keys 1 to 6")
            }
            row("Blur radius") {
                HStack {
                    Slider(value: blurRadius, in: RedactionDefaults.blurRangePoints, step: 1)
                    readout(model.blurRadiusPoints)
                }
            }
            .disabled(effectTool != .blur)
            row("Pixel block") {
                HStack {
                    Slider(value: block, in: RedactionDefaults.blockRangePoints, step: 1)
                    readout(model.blockPoints)
                }
            }
            .disabled(effectTool != .pixelate)
            row("Shape") {
                Picker("Shape", selection: spotlightShape) {
                    Text("Rectangle").tag(false)
                    Text("Ellipse").tag(true)
                }
            }
            .disabled(!model.spotlightShapeApplies)
            row("Dim") {
                Picker("Dim", selection: spotlightDim) {
                    ForEach(EditorPalette.spotlightDims, id: \.self) { dim in
                        Text("\(Int((dim * 100).rounded())) %").tag(dim)
                    }
                }
            }
            .disabled(!model.spotlightDimApplies)
            row("Size") {
                Picker("Size", selection: counterSize) {
                    ForEach(Array(zip(Self.counterSizeLabels, EditorPalette.counterDiametersPoints)), id: \.1) { label, points in
                        Text(label).tag(points)
                    }
                }
            }
            .disabled(!model.counterSizeApplies)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(12)
        .frame(width: Self.width)
    }

    /// One row: the label right-aligned in the first column, on one line, then the control.
    private func row(_ label: String, @ViewBuilder control: () -> some View) -> some View {
        GridRow {
            OptionLabel(text: label)
                .gridColumnAlignment(.trailing)
            control()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func readout(_ points: CGFloat) -> some View {
        Text("\(Int(points)) pt")
            .monospacedDigit()
            .frame(width: 40, alignment: .trailing)
    }

    /// The effect the sliders act on: the selected annotation's kind, else the active tool's.
    private var effectTool: EditorTool? {
        switch model.selectedAnnotation {
        case .blur?: .blur
        case .pixelate?: .pixelate
        default: model.tool == .blur || model.tool == .pixelate ? model.tool : nil
        }
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

    private var counterSize: Binding<CGFloat> {
        Binding(get: { model.activeCounterDiameterPoints }, set: { model.applyCounterSize(points: $0) })
    }
}

/// A row's label: one line, never squeezed, dimmed with the row when it does not apply, as a
/// `Form` label is.
private struct OptionLabel: View {
    let text: String
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Text(text)
            .foregroundStyle(isEnabled ? .primary : .secondary)
            .lineLimit(1)
            .fixedSize()
    }
}
