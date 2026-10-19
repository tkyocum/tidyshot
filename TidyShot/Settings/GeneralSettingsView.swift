import SwiftUI

struct GeneralSettingsView: View {
    @Bindable private var settings = AppSettings.shared
    private let saveLocation = AppCoordinator.shared.saveLocation

    var body: some View {
        Form {
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
            Text("Tokens: {date} {time} {datetime} {app} {counter} {random} {random:8}")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Copy image to clipboard", isOn: $settings.copyImageToClipboard)
            Toggle("Show notification", isOn: $settings.showNotification)
            Toggle("Play sound", isOn: $settings.playSound)
        }
        .formStyle(.grouped)
    }
}
