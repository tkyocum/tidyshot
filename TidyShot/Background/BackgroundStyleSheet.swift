import SwiftUI

/// The Capture tab's `Edit Background…` sheet (spec 2.11): the style editor bound to
/// `AppSettings.backgroundStyle`, which stores each change itself, and `Done`.
struct BackgroundStyleSheet: View {
    @Bindable var settings: AppSettings
    let onUnusableImage: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            BackgroundOptionsView(style: $settings.backgroundStyle, onCommit: {},
                                  onUnusableImage: onUnusableImage)
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}
