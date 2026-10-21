import SwiftUI

struct CaptureSettingsView: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Form {
            Toggle("Freeze screen while selecting", isOn: $settings.freezeScreen)
            Text("Area selections show a still image of the screen and the capture is cut from it, so menus, tooltips and video stay as they were when you pressed the shortcut.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Show cursor in screenshots", isOn: $settings.showsCursor)
            Text("Fullscreen, previous-area, self-timer and URL captures show the pointer where it is. Area captures show it only with Freeze screen on. TidyShot never captures its own crosshair.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Include window shadow", isOn: $settings.windowShadow)
            Text("Window captures keep transparent rounded corners either way.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Self-timer", selection: $settings.selfTimerSeconds) {
                ForEach(AppSettings.selfTimerChoices, id: \.self) { seconds in
                    Text("\(seconds) seconds").tag(seconds)
                }
            }
        }
        .formStyle(.grouped)
    }
}
