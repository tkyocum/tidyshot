import SwiftUI

/// The scrolling capture panel's content (spec 2.8, The session): the preview anchored to its
/// bottom so the newest rows show, the size readout in image pixels, the status line, and Cancel
/// with Start, then Cancel with Done.
struct ScrollCaptureView: View {
    static let padding: CGFloat = 12
    /// The panel's height without the preview, in points: the readout, the status line at two
    /// lines, the buttons, the spacing and the padding. Measured in Step 10.
    static let chromeHeight: CGFloat = 120
    static var previewWidth: CGFloat { ScrollPanelGeometry.panelWidth - 2 * padding }

    /// The preview's height when drawn `previewWidth` wide; 0 without one.
    static func previewHeight(for image: CGImage?) -> CGFloat {
        guard let image, image.width > 0 else { return 0 }
        return CGFloat(image.height) * previewWidth / CGFloat(image.width)
    }

    let session: ScrollCaptureSession
    let onAllowAutoScroll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            preview
            Text(ScrollCaptureStatus.sizeText(width: session.widthPixels, height: session.heightPixels))
                .font(.callout.monospacedDigit())
            Text(session.status.text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.updatesFrequently)
            if session.phase == .ready {
                Toggle("Scroll automatically", isOn: Binding(get: { session.usesAutoScroll },
                                                              set: { session.autoScroll = $0 }))
                    .disabled(!session.isAutoScrollPermitted)
                if !session.isAutoScrollAvailable {
                    Text("Auto-scroll is unavailable: macOS did not deliver TidyShot's scroll events.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !session.isAutoScrollPermitted {
                    Button("Allow Auto-Scroll…", action: onAllowAutoScroll)
                        .buttonStyle(.link)
                }
            }
            buttons
        }
        .padding(Self.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        // Notices the grant while the panel waits for Start.
        .task {
            while !Task.isCancelled, session.phase == .ready {
                session.refreshAutoScrollPermission()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var preview: some View {
        GeometryReader { geometry in
            Group {
                if let image = session.preview, image.width > 0 {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.medium)
                        .frame(width: geometry.size.width,
                               height: CGFloat(image.height) * geometry.size.width / CGFloat(image.width))
                } else {
                    RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottom)
            .clipped()
        }
        .accessibilityElement()
        .accessibilityLabel("Preview")
    }

    private var buttons: some View {
        HStack {
            Spacer()
            Button("Cancel") { Task { await session.cancel() } }
                .keyboardShortcut(.cancelAction)
                .disabled(session.phase == .ended)
            if session.phase == .ready {
                Button("Start") { Task { await session.start() } }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Done") { Task { await session.done() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canFinish)
            }
        }
    }

    /// Done needs a first frame and a capture still running.
    private var canFinish: Bool {
        guard case .capturing = session.phase else { return false }
        return session.hasFirstFrame
    }
}
