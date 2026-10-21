import SwiftUI

struct CaptureSettingsView: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Form {
            Toggle("Show cursor in screenshots", isOn: $settings.showsCursor)
            Text("Fullscreen, previous-area, self-timer and URL captures show the pointer where it is. Area captures show it only with Freeze screen on. TidyShot never captures its own crosshair.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Include window shadow", isOn: $settings.windowShadow)
            Text("Window captures keep transparent rounded corners either way.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}
