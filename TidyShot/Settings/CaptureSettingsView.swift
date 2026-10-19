import SwiftUI

struct CaptureSettingsView: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Form {
            Toggle("Show cursor in screenshots", isOn: $settings.showsCursor)
        }
        .formStyle(.grouped)
    }
}
