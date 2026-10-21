import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Edits a `BackgroundStyle` (spec 2.11, Style editor): the editor's Background popover and the
/// Capture tab's style sheet both use it. Sliders show live and call `onCommit` when a drag ends;
/// every other change calls it at once. A custom image that does not decode is handed to
/// `onUnusableImage` by file name, so the owner can post `Not a usable image`.
struct BackgroundOptionsView: View {
    @Binding var style: BackgroundStyle
    let onCommit: () -> Void
    let onUnusableImage: (String) -> Void

    /// The custom swatch's picture, read off the main actor; nil when there is no stored image.
    @State private var customPreview: CGImage?
    /// The last solid colour picked here, which the solid swatch shows while another fill is chosen.
    @State private var lastSolidColor = RGBA(hex: 0xFFFFFF)

    private static let swatchSize = CGSize(width: 44, height: 30)
    private static let swatchRadius: CGFloat = 6

    init(style: Binding<BackgroundStyle>, onCommit: @escaping () -> Void,
         onUnusableImage: @escaping (String) -> Void) {
        _style = style
        self.onCommit = onCommit
        self.onUnusableImage = onUnusableImage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            swatchGrid
            if customPreview != nil {
                HStack {
                    Spacer()
                    Button("Choose Image…") { chooseImage() }
                        .controlSize(.small)
                }
            }
            slider("Padding", value: $style.padding, range: 0...160)
            slider("Corner Radius", value: $style.cornerRadius, range: 0...40)
            Toggle("Shadow", isOn: committing(\.shadow))
            Picker("Aspect Ratio", selection: committing(\.aspect)) {
                ForEach(BackgroundAspect.allCases, id: \.self) { aspect in
                    Text(aspect.title).tag(aspect)
                }
            }
        }
        // Every view showing the image reads it again after a store, here or in another window.
        .task(id: CustomBackgroundRevision.shared.count) {
            customPreview = await Task.detached(priority: .userInitiated) {
                CustomBackgroundStore.shared.preview(maxSide: 128)
            }.value
        }
    }

    // MARK: Swatches

    private var swatchGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(Self.swatchSize.width), spacing: 8), count: 5),
                  spacing: 8) {
            ForEach(Array(BackgroundPresets.gradients.enumerated()), id: \.offset) { index, preset in
                swatch(.gradient(index), name: preset.name) {
                    LinearGradient(colors: [Color(cgColor: preset.first.cgColor), Color(cgColor: preset.second.cgColor)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            swatch(.desktopPicture, name: "Desktop Picture") {
                Image(systemName: "menubar.dock.rectangle")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary)
            }
            solidSwatch
            customSwatch
        }
    }

    /// A button that chooses `fill`, with an accent ring while it is the style's fill.
    private func swatch(_ fill: BackgroundFill, name: String, @ViewBuilder content: () -> some View) -> some View {
        Button {
            choose(fill)
        } label: {
            swatchFace(selected: isSelected(fill), content: content)
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected(fill) ? .isSelected : [])
    }

    private func swatchFace(selected: Bool, @ViewBuilder content: () -> some View) -> some View {
        content()
            .frame(width: Self.swatchSize.width, height: Self.swatchSize.height)
            .clipShape(RoundedRectangle(cornerRadius: Self.swatchRadius))
            .overlay(RoundedRectangle(cornerRadius: Self.swatchRadius).strokeBorder(.separator))
            .padding(3)
            .overlay(RoundedRectangle(cornerRadius: Self.swatchRadius + 3)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .opacity(selected ? 1 : 0))
            .frame(width: Self.swatchSize.width, height: Self.swatchSize.height)
    }

    /// The style's solid colour, or the last one picked while another fill is chosen.
    private var solidColor: RGBA {
        if case .solid(let color) = style.fill { color } else { lastSolidColor }
    }

    /// A colour well: picking a colour chooses the solid fill.
    private var solidSwatch: some View {
        let selected = isSelected(.solid(solidColor))
        return ColorPicker("Solid Colour", selection: solidBinding, supportsOpacity: false)
            .labelsHidden()
            .padding(3)
            .overlay(RoundedRectangle(cornerRadius: Self.swatchRadius + 3)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .opacity(selected ? 1 : 0))
            .frame(width: Self.swatchSize.width, height: Self.swatchSize.height)
            .help("Solid Colour")
            .accessibilityLabel("Solid Colour")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The stored image, or a `photo` symbol that chooses one when there is none.
    @ViewBuilder
    private var customSwatch: some View {
        if let customPreview {
            swatch(.customImage, name: "Custom Image") {
                Image(decorative: customPreview, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        } else {
            Button {
                chooseImage()
            } label: {
                swatchFace(selected: false) {
                    Image(systemName: "photo")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.quaternary)
                }
            }
            .buttonStyle(.plain)
            .help("Choose Image…")
            .accessibilityLabel("Custom Image, Choose Image…")
        }
    }

    private func isSelected(_ fill: BackgroundFill) -> Bool {
        switch (style.fill, fill) {
        case (.solid, .solid): true
        default: style.fill == fill
        }
    }

    private func choose(_ fill: BackgroundFill) {
        guard style.fill != fill else { return }
        style.fill = fill
        onCommit()
    }

    /// The colour panel can hand back Display P3 or grey colours; they are converted to sRGB.
    private var solidBinding: Binding<CGColor> {
        Binding(get: { solidColor.cgColor },
                set: { color in
                    guard let rgba = RGBA(srgbConverting: color) else { return }
                    lastSolidColor = rgba
                    choose(.solid(rgba))
                })
    }

    // MARK: Custom image

    /// Opens a panel for one image, stores it off the main actor and chooses the custom fill. A
    /// file that does not decode goes to `onUnusableImage`, and nothing changes.
    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        Task {
            guard await panel.begin() == .OK, let url = panel.url else { return }
            let outcome = await Task.detached(priority: .userInitiated) { () -> Result<Void, any Error> in
                Result { try CustomBackgroundStore.shared.store(contentsOf: url) }
            }.value
            switch outcome {
            case .success:
                CustomBackgroundRevision.shared.bump()
                choose(.customImage)
            case .failure(CustomBackgroundStore.StoreError.notAnImage):
                onUnusableImage(url.lastPathComponent)
            case .failure(let error):
                // The image decoded but could not be written; the stored one is kept.
                NSLog("The custom background could not be stored: \(error.localizedDescription)")
            }
        }
    }

    // MARK: Controls

    /// A labelled slider whose drag shows live and commits once, when it ends.
    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title)
            Slider(value: value, in: range, step: 1) { editing in
                if !editing { onCommit() }
            }
            Text("\(Int(value.wrappedValue.rounded())) pt")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }

    /// A binding to one field of the style that commits on every change.
    private func committing<Value: Equatable>(_ keyPath: WritableKeyPath<BackgroundStyle, Value>) -> Binding<Value> {
        Binding(get: { style[keyPath: keyPath] },
                set: { newValue in
                    guard style[keyPath: keyPath] != newValue else { return }
                    style[keyPath: keyPath] = newValue
                    onCommit()
                })
    }
}
