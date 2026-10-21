import SwiftUI

struct GeneralSettingsView: View {
    @Bindable private var settings = AppSettings.shared
    private let saveLocation = AppCoordinator.shared.saveLocation

    var body: some View {
        Form {
            Section {
                LabeledContent("Save to") {
                    HStack {
                        Text(saveLocation.currentURL?.path(percentEncoded: false) ?? "Not set")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Choose…") {
                            Task { _ = await saveLocation.chooseFolder() }
                        }
                    }
                }
                TextField("File name", text: $settings.fileNameTemplate)
                Text("Tokens: \(TemplateExpander.tokenList)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("After capture", selection: $settings.afterCaptureAction) {
                    ForEach(AfterCaptureAction.allCases) { action in
                        Text(action.title).tag(action)
                    }
                }
                if settings.afterCaptureAction.uploads {
                    Toggle("Also copy image (the URL replaces it when the upload finishes)", isOn: $settings.alsoCopyImageWhenUploading)
                } else {
                    Toggle("Copy image to clipboard", isOn: $settings.copyImageToClipboard)
                }
                if settings.afterCaptureAction == .uploadOnly {
                    Text("The PNG is kept inside TidyShot only until the upload succeeds. Recent Captures keeps a thumbnail and the URL; a failed upload keeps the file until you retry or delete it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Show notification", isOn: $settings.showNotification)
                Toggle("Play sound", isOn: $settings.playSound)
            }
            Section("URL commands") {
                Toggle("Allow URL commands (tidyshot://)", isOn: $settings.urlCommandsEnabled)
                Toggle("Allow URL commands that capture without a selection", isOn: $settings.urlCommandsAllowSilent)
                    .disabled(!settings.urlCommandsEnabled)
                Text("capture-fullscreen, capture-previous-area and capture-area with x, y, width and height capture at once. Any app on this Mac, and any web page you let open TidyShot, can send them, and an allowed command lets the sending app read the result from the clipboard.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
