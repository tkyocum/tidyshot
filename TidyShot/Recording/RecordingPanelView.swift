import Observation
import SwiftUI

/// What the recording panel shows, and what its buttons call.
@Observable
final class RecordingPanelModel {
    /// Seconds since the first frame.
    var elapsed: TimeInterval = 0
    /// False once the recording is ending: Stop and Cancel then do nothing.
    var stopEnabled = true
    @ObservationIgnored var onStop: () -> Void = {}
    @ObservationIgnored var onCancel: () -> Void = {}
}

/// The recording's control bar (design, Control panel): the elapsed time, orange from the 5:00
/// soft limit, then Stop and Cancel.
struct RecordingPanelView: View {
    /// A 172 × 44 pt bar (plan Gap 8).
    static let size = CGSize(width: 172, height: 44)

    let model: RecordingPanelModel

    var body: some View {
        HStack(spacing: 6) {
            Text(RecordingClock.format(model.elapsed))
                .font(.system(size: 15, weight: .medium).monospacedDigit())
                .foregroundStyle(RecordingClock.isPastSoftLimit(model.elapsed, format: .mp4) ? Color.orange : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                model.onStop()
            } label: {
                Image(systemName: "stop.fill")
                    .foregroundStyle(.red)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Stop")
            Button {
                model.onCancel()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .help("Discard the recording")
            .accessibilityLabel("Cancel")
        }
        .buttonStyle(.borderless)
        .font(.system(size: 14, weight: .semibold))
        .disabled(!model.stopEnabled)
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(.regularMaterial, in: Capsule())
        .contentShape(Capsule())
        // The panel never becomes key, so the bar is dragged by this gesture as well as by
        // `isMovableByWindowBackground`.
        .gesture(WindowDragGesture())
    }
}
