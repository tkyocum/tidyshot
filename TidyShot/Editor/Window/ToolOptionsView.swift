import SwiftUI

/// The options popover (spec 2.6, Palette and options): line width, blur radius and pixel block.
/// Each control applies live through `EditorModel`, which commits a selected annotation under a
/// coalescing key, so one slider drag is one undo step. Only the slider for the effect in play is
/// enabled: the selected blur or pixelate, else the active Blur or Pixelate tool. A selected
/// annotation of another kind does not decide it, so with a rectangle selected the active effect
/// tool's slider still works and sets only the default.
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
        Binding(get: { model.lineWidthPoints }, set: { model.applyLineWidth(points: $0) })
    }

    private var blurRadius: Binding<CGFloat> {
        Binding(get: { model.blurRadiusPoints }, set: { model.applyEffectParameter(.blurRadius, points: $0) })
    }

    private var block: Binding<CGFloat> {
        Binding(get: { model.blockPoints }, set: { model.applyEffectParameter(.block, points: $0) })
    }
}
