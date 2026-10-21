import CoreGraphics
import SwiftUI

/// The colour popover (spec 2.6, Palette and options): ten swatches and a custom colour. A pick goes
/// through `EditorModel.applyColor(_:)`, which sets the active tool's colour and recolours the
/// selected annotation. No background: the popover's glass is the backdrop.
struct ColorPaletteView: View {
    let model: EditorModel

    /// Names for `EditorPalette.swatches`, in the spec's order, for help tags and VoiceOver.
    private static let names = ["Black", "Red", "Orange", "Yellow", "Green", "Teal", "Blue", "Purple", "Pink", "White"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(22), spacing: 8), count: 5), spacing: 8) {
                ForEach(Array(EditorPalette.swatches.enumerated()), id: \.offset) { index, swatch in
                    swatchButton(swatch, name: index < Self.names.count ? Self.names[index] : "Colour \(index + 1)")
                }
            }
            ColorPicker("Custom", selection: customColor, supportsOpacity: false)
        }
        .padding(12)
    }

    private func swatchButton(_ swatch: RGBA, name: String) -> some View {
        let isCurrent = model.activeColor == swatch
        return Button {
            model.applyColor(swatch)
        } label: {
            Circle()
                .fill(Color(cgColor: swatch.cgColor))
                .overlay(Circle().strokeBorder(.separator))  // so white shows
                .padding(3)
                .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2).opacity(isCurrent ? 1 : 0))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    /// The colour panel can hand back Display P3 or grey colours; they are converted to sRGB.
    private var customColor: Binding<CGColor> {
        Binding(get: { model.activeColor.cgColor },
                set: { color in
                    if let rgba = RGBA(srgbConverting: color) { model.applyColor(rgba) }
                })
    }
}

extension RGBA {
    /// `color` in sRGB with each component clamped to 0...1, or nil when it has no RGB form (a
    /// pattern). The picker has no opacity, so alpha is always 1.
    init?(srgbConverting color: CGColor) {
        guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = color.converted(to: sRGB, intent: .defaultIntent, options: nil),
              let components = converted.components, components.count >= 3 else { return nil }
        let clamped = components.prefix(3).map { Double(min(max($0, 0), 1)) }
        self.init(red: clamped[0], green: clamped[1], blue: clamped[2], alpha: 1)
    }
}
