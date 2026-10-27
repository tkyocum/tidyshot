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
    /// `Camera`'s list and the access, read as the microphone's are.
    @State private var cameraDevices: [CameraDevice] = []
    @State private var cameraAccess = CameraAccess.authorized
    /// The Settings window, so another window becoming key does not count.
    @State private var settingsWindow: ObjectIdentifier?

    /// A SwiftUI `Picker` has no menu-will-open hook, so the list refreshes when an input comes or goes.
    private static let microphoneChanges = Publishers.MergeMany(
        LiveMicrophoneDevices.changeNotifications.map { NotificationCenter.default.publisher(for: $0) })
        .receive(on: DispatchQueue.main)
    /// The camera list refreshes when a camera comes or goes, as the microphone's does.
    private static let cameraChanges = Publishers.MergeMany(
        LiveCameraDevices.changeNotifications.map { NotificationCenter.default.publisher(for: $0) })
        .receive(on: DispatchQueue.main)

    /// Which Recording rows show and which are enabled, for the chosen format.
    private var recordingLayout: RecordingSettingsLayout {
        RecordingSettingsLayout(format: settings.recordingFormat,
                                clickHighlights: settings.recordingClickHighlights,
                                webcamBubble: settings.recordingWebcamBubble)
    }

    /// The same `AVCaptureDevice` reads the recorder's `microphones` makes; it holds no state.
    private let microphones: any MicrophoneDevices = LiveMicrophoneDevices()

    private var storedMicrophone: MicrophoneChoice.Stored {
        MicrophoneChoice.Stored(value: settings.recordingMicrophone, name: settings.recordingMicrophoneName)
    }

    /// The same `AVCaptureDevice` reads the coordinator's `cameras` makes; it holds no state.
    private let cameras: any CameraDevices = LiveCameraDevices()

    private var storedCamera: CameraChoice.Stored {
        CameraChoice.Stored(value: settings.recordingCamera, name: settings.recordingCameraName)
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
                Toggle("Highlight clicks", isOn: $settings.recordingClickHighlights)
                Toggle("Show webcam bubble", isOn: Binding(get: { settings.recordingWebcamBubble }, set: setWebcamBubble))
                Picker("Camera", selection: Binding(get: { storedCamera.value }, set: pickCamera)) {
                    ForEach(CameraChoice.entries(stored: storedCamera, devices: cameraDevices), id: \.tag) { entry in
                        Text(entry.title).tag(entry.tag)
                    }
                }
                .disabled(!recordingLayout.cameraRowsEnabled)
                if CameraChoice.showsAccessNote(bubble: settings.recordingWebcamBubble, access: cameraAccess) {
                    HStack {
                        Text(CameraChoice.accessOffText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Privacy Settings…") {
                            NSWorkspace.shared.open(CameraChoice.privacySettingsURL)
                        }
                    }
                }
                Picker("Bubble size", selection: $settings.recordingBubbleSize) {
                    ForEach(BubbleSize.allCases, id: \.self) { size in
                        Text(size.title).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!recordingLayout.cameraRowsEnabled)
                if recordingLayout.showsBubbleGIFCaption {
                    Text(RecordingSettingsLayout.bubbleGIFCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if recordingLayout.showsOverlayCaption {
                    Text(RecordingSettingsLayout.overlayCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $editingBackground) {
            BackgroundStyleSheet(settings: settings, onUnusableImage: { name in
                AppCoordinator.shared.notifyUnusableBackgroundImage(named: name)
            })
        }
        .background(WindowReader { settingsWindow = $0.map(ObjectIdentifier.init) })
        .onAppear {
            refreshMicrophones()
            refreshCameras()
        }
        .onReceive(Self.microphoneChanges) { _ in refreshMicrophones() }
        .onReceive(Self.cameraChanges) { _ in refreshCameras() }
        // Back from System Settings, the notes clear once access is allowed.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            guard let window = notification.object as? NSWindow, ObjectIdentifier(window) == settingsWindow else { return }
            microphoneAccess = microphones.access()
            cameraAccess = cameras.access()
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

    /// A pick writes the choice and the device's name, whatever the access (`MicrophoneChoice.pick`;
    /// design, Microphone, Permission). A microphone picked while access is not determined asks for
    /// it through the coordinator, which waits while a capture, a recording or another prompt runs
    /// (R3 design, Asking from Settings). The answer changes nothing stored: after a refusal, or a
    /// pick while access is off, the row shows the access note.
    private func pickMicrophone(_ tag: String) {
        let name = microphoneDevices.first { $0.uniqueID == tag }?.name
            ?? (tag == settings.recordingMicrophone ? settings.recordingMicrophoneName : "")
        microphoneAccess = microphones.access()
        let pick = MicrophoneChoice.pick(MicrophoneChoice.Stored(value: tag, name: name), access: microphoneAccess)
        settings.recordingMicrophone = pick.stored.value
        settings.recordingMicrophoneName = pick.stored.name
        guard pick.asksForAccess else { return }
        Task {
            await AppCoordinator.shared.requestAccessFromSettings(.microphone)
            microphoneAccess = microphones.access()
        }
    }

    /// Reads the cameras and the access. A stored camera that is listed under another name gets
    /// the new name written (`CameraChoice.refreshedName`).
    private func refreshCameras() {
        cameraDevices = cameras.list()
        cameraAccess = cameras.access()
        if let name = CameraChoice.refreshedName(stored: storedCamera, devices: cameraDevices) {
            settings.recordingCameraName = name
        }
    }

    /// A pick writes the camera and its name (`CameraChoice.pick`), whatever the access.
    private func pickCamera(_ tag: String) {
        let picked = CameraChoice.pick(tag: tag, devices: cameraDevices, stored: storedCamera)
        settings.recordingCamera = picked.value
        settings.recordingCameraName = picked.name
    }

    /// `Show webcam bubble` turned on while camera access is not determined asks for it through the
    /// coordinator (R3 design, Asking from Settings), which waits while a capture, a recording or
    /// another prompt runs; the next start then asks. The toggle stays on whatever the answer
    /// (Decided 2026-10-24, 7): after a refusal the rows show the access note.
    private func setWebcamBubble(_ on: Bool) {
        settings.recordingWebcamBubble = on
        cameraAccess = cameras.access()
        guard CameraChoice.asksForAccess(bubble: on, access: cameraAccess) else { return }
        Task {
            await AppCoordinator.shared.requestAccessFromSettings(.camera)
            cameraAccess = cameras.access()
        }
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
