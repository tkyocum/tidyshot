import AppKit
import Combine
import SwiftUI

struct CaptureSettingsView: View {
    @Bindable private var settings = AppSettings.shared
    @State private var editingBackground = false
    /// `Microphone`'s inputs and the access, read when the tab appears and again on the device
    /// notifications; the access also when the Settings window becomes key.
    @State private var microphoneDevices: [MicrophoneDevice] = []
    @State private var microphoneAccess = MicrophoneAccess.authorized
    /// The Settings window, so another window becoming key does not count.
    @State private var settingsWindow: ObjectIdentifier?

    /// A SwiftUI `Picker` has no menu-will-open hook, so the list refreshes when an input comes or goes.
    private static let microphoneChanges = Publishers.MergeMany(
        LiveMicrophoneDevices.changeNotifications.map { NotificationCenter.default.publisher(for: $0) })
        .receive(on: DispatchQueue.main)

    /// Which Recording rows show and which are enabled, for the chosen format.
    private var recordingLayout: RecordingSettingsLayout {
        RecordingSettingsLayout(format: settings.recordingFormat)
    }

    private var microphones: any MicrophoneDevices {
        AppCoordinator.shared.microphones
    }

    private var storedMicrophone: MicrophoneChoice.Stored {
        MicrophoneChoice.Stored(value: settings.recordingMicrophone, name: settings.recordingMicrophoneName)
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
                Picker("Microphone", selection: Binding(get: { settings.recordingMicrophone }, set: pickMicrophone)) {
                    ForEach(MicrophoneChoice.entries(stored: storedMicrophone, devices: microphoneDevices), id: \.tag) { entry in
                        Text(entry.title).tag(entry.tag)
                    }
                }
                .disabled(!recordingLayout.audioRowsEnabled)
                if MicrophoneChoice.showsAccessNote(stored: storedMicrophone, access: microphoneAccess) {
                    HStack {
                        Text(MicrophoneChoice.accessOffText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Privacy Settings…") {
                            NSWorkspace.shared.open(MicrophoneChoice.privacySettingsURL)
                        }
                    }
                }
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
        .background(WindowReader { settingsWindow = $0.map(ObjectIdentifier.init) })
        .onAppear(perform: refreshMicrophones)
        .onReceive(Self.microphoneChanges) { _ in refreshMicrophones() }
        // Back from System Settings, the note clears once access is allowed.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            guard let window = notification.object as? NSWindow, ObjectIdentifier(window) == settingsWindow else { return }
            microphoneAccess = microphones.access()
        }
    }

    /// Reads the inputs and the access. A stored device that is listed gets its name written
    /// again, as a disconnected `uniqueID` cannot be turned back into a name.
    private func refreshMicrophones() {
        microphoneDevices = microphones.list()
        microphoneAccess = microphones.access()
        if case .device(let id, let name) = storedMicrophone,
           let device = microphoneDevices.first(where: { $0.uniqueID == id }), device.name != name {
            settings.recordingMicrophoneName = device.name
        }
    }

    /// A pick writes the choice and the device's name (design, Microphone, Permission). A pick
    /// while access is not determined asks for it; a refusal, or a pick while access is denied,
    /// goes back to Off.
    private func pickMicrophone(_ tag: String) {
        let name = microphoneDevices.first { $0.uniqueID == tag }?.name
            ?? (tag == settings.recordingMicrophone ? settings.recordingMicrophoneName : "")
        microphoneAccess = microphones.access()
        guard MicrophoneChoice.Stored(value: tag, name: name) != .off else {
            setMicrophone(tag, name: name)
            return
        }
        switch microphoneAccess {
        case .authorized:
            setMicrophone(tag, name: name)
        case .denied, .restricted:
            setMicrophone("", name: "")
        case .notDetermined:
            setMicrophone(tag, name: name)
            Task {
                let granted = await microphones.requestAccess()
                microphoneAccess = microphones.access()
                if !granted {
                    setMicrophone("", name: "")
                }
            }
        }
    }

    private func setMicrophone(_ value: String, name: String) {
        settings.recordingMicrophone = value
        settings.recordingMicrophoneName = name
    }
}

/// Reports the window its view is in, once it is in one.
private struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        WindowReportingView(onWindow: onWindow)
    }

    func updateNSView(_ view: NSView, context: Context) {}

    private final class WindowReportingView: NSView {
        let onWindow: (NSWindow?) -> Void

        init(onWindow: @escaping (NSWindow?) -> Void) {
            self.onWindow = onWindow
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not used")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // After SwiftUI's update, so the state change is not made during it.
            let window = window
            DispatchQueue.main.async { [onWindow] in onWindow(window) }
        }
    }
}
