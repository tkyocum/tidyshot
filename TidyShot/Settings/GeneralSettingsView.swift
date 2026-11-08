import SwiftUI

struct GeneralSettingsView: View {
    @Bindable private var settings = AppSettings.shared
    private let saveLocation = AppCoordinator.shared.saveLocation
    /// Whether either Clop build is installed, read once when the tab appears (the lookup asks
    /// LaunchServices, so it does not belong in a property initialiser that runs on every rebuild).
    @State private var clopInstalled = false

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
                TextField("Recording file name", text: $settings.recordingFileNameTemplate)
                Caption("Tokens: \(TemplateExpander.tokenList)")
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
                Caption("For recordings, the file is copied.")
                if settings.afterCaptureAction == .uploadOnly {
                    Caption("The file is kept inside TidyShot only until the upload succeeds. Recent Captures keeps a thumbnail and the URL; a failed upload keeps the file until you retry or delete it.")
                }
                Toggle("Show notification", isOn: $settings.showNotification)
                Toggle("Play sound", isOn: $settings.playSound)
                Toggle("Ask before deleting", isOn: $settings.confirmBeforeDeleting)
                Caption("Delete removes the file, the upload and the Recent Captures entry. When this is off, Delete acts at once.")
            }
            Section("Optimization") {
                Toggle("Optimize images and videos with Clop", isOn: $settings.optimiseWithClop)
                    .disabled(!clopInstalled)
                Caption("Clop greatly reduces file size. It keeps its own copy of each image and video it optimizes, so long recordings also take space in Clop's cache.")
                if !clopInstalled {
                    Link("Get Clop", destination: URL(string: "https://lowtechguys.com/clop")!)
                        .font(.caption)
                }
            }
            Section("URL commands") {
                Toggle("Allow URL commands (tidyshot://)", isOn: $settings.urlCommandsEnabled)
                Toggle("Allow URL commands that capture without a selection", isOn: $settings.urlCommandsAllowSilent)
                    .disabled(!settings.urlCommandsEnabled)
                Caption("capture-fullscreen, capture-previous-area, and capture-area or capture-text with x, y, width and height capture at once. Any app on this Mac, and any web page you let open TidyShot, can send them, and an allowed command lets the sending app read the result from the clipboard.")
            }
        }
        .formStyle(.grouped)
        .onAppear { clopInstalled = ClopApp.isInstalled }
    }
}
