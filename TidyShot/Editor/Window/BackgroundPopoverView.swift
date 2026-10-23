import SwiftUI

/// The Background popover (spec 2.11, Editor): a `Background` toggle, then the style editor.
/// Turning the background on starts from the Capture tab's style (`AppSettings.backgroundStyle`);
/// turning it off keeps nothing. The style editor writes to `EditorModel.backgroundDraft`, which
/// the canvas shows live, and its `onCommit` makes each swatch, slider drag, toggle and picker
/// change one step. With the background off it shows the style the toggle would start from,
/// disabled.
struct BackgroundPopoverView: View {
    let model: EditorModel
    let onUnusableImage: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Background", isOn: isOn)
                    .toggleStyle(.switch)
                    .disabled(!isOn.wrappedValue && !fits)
                if !fits {
                    Text("Backgrounds work on images up to 16,384 px.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Divider()
            BackgroundOptionsView(style: style, onCommit: { model.commitBackgroundDraft() },
                                  onUnusableImage: onUnusableImage)
                .disabled(model.document.background == nil)
        }
        .padding(16)
        .frame(width: 332)
        // A slider drag the popover's closing cut short is still one step.
        .onDisappear { model.commitBackgroundDraft() }
    }

    private var isOn: Binding<Bool> {
        Binding(get: { model.document.background != nil },
                set: { on in model.setBackground(on ? AppSettings.shared.backgroundStyle : nil) })
    }

    /// False when the content (the crop, or the whole capture) is over 16,384 px on a side.
    private var fits: Bool {
        model.backgroundFits(model.document.background ?? AppSettings.shared.backgroundStyle)
    }

    private var style: Binding<BackgroundStyle> {
        Binding(get: { model.backgroundDraft ?? model.document.background ?? AppSettings.shared.backgroundStyle },
                set: { style in
                    guard model.document.background != nil else { return }
                    model.backgroundDraft = style
                })
    }
}
