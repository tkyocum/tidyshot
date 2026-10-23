import SwiftUI

struct CaptureSettingsView: View {
    @Bindable private var settings = AppSettings.shared
    @State private var editingBackground = false

    /// Which Recording rows show and which are enabled, for the chosen format.
    private var recordingLayout: RecordingSettingsLayout {
        RecordingSettingsLayout(format: settings.recordingFormat)
    }

    var body: some View {
        Form {
            Section {
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
                Toggle("Hide desktop icons while capturing", isOn: $settings.hideDesktopIconsWhileCapturing)
                Text("Covers desktop icons and widgets with the desktop picture during area, window, fullscreen, previous-area, All-in-One and self-timer captures, and area and fullscreen recordings. While covered, the desktop does not take clicks.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Add background to window captures", isOn: $settings.windowBackground)
                Text("Puts each window capture on the background below, as the editor's Background tool would.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Edit Background…") { editingBackground = true }
                Picker("Self-timer", selection: $settings.selfTimerSeconds) {
                    ForEach(AppSettings.selfTimerChoices, id: \.self) { seconds in
                        Text("\(seconds) seconds").tag(seconds)
                    }
                }
            }
            Section("Recording") {
                Picker("Format", selection: $settings.recordingFormat) {
                    Text("MP4").tag(RecordingFormat.mp4)
                    Text("GIF").tag(RecordingFormat.gif)
                }
                if recordingLayout.showsGIFRows {
                    Picker("GIF frame rate", selection: $settings.gifFrameRate) {
                        ForEach(AppSettings.gifFrameRates, id: \.self) { rate in
                            Text("\(rate) fps").tag(rate)
                        }
                    }
                    Picker("GIF size", selection: $settings.gifMaxSide) {
                        ForEach(AppSettings.gifMaxSides, id: \.self) { side in
                            Text(side == 0 ? "Full size" : "\(side) px").tag(side)
                        }
                    }
                    Text(RecordingSettingsLayout.fullSizeCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if recordingLayout.showsFrameRate {
                    Picker("Frame rate", selection: $settings.recordingFrameRate) {
                        ForEach(AppSettings.recordingFrameRates, id: \.self) { rate in
                            Text("\(rate) fps").tag(rate)
                        }
                    }
                }
                Picker("Resolution", selection: $settings.recordingRetina) {
                    Text("Retina").tag(true)
                    Text("Standard").tag(false)
                }
                Text("Retina is capped at 4096 px on the longer side.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Record system audio", isOn: $settings.recordingSystemAudio)
                    .disabled(!recordingLayout.audioRowsEnabled)
                if recordingLayout.showsGIFCaption {
                    Text(RecordingSettingsLayout.gifCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Show cursor in recordings", isOn: $settings.recordingShowsCursor)
                Toggle("Count down before recording", isOn: $settings.recordingCountdown)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $editingBackground) {
            BackgroundStyleSheet(settings: settings, onUnusableImage: { name in
                AppCoordinator.shared.notifyUnusableBackgroundImage(named: name)
            })
        }
    }
}
