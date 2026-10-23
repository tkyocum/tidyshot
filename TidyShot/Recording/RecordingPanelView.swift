import Observation
import SwiftUI

/// What the recording panel shows, and what its buttons call.
@Observable
final class RecordingPanelModel {
    /// Seconds since the first frame.
    var elapsed: TimeInterval = 0
    /// False once the recording is ending: Stop and Cancel then do nothing.
    var stopEnabled = true
    /// Set at `show`, before the panel is laid out.
    var bar: RecordingPanelLayout.Bar = .plain
    @ObservationIgnored var onStop: () -> Void = {}
    @ObservationIgnored var onCancel: () -> Void = {}

    /// The recording's format, for the soft limit: only a GIF recording has the GIF bar.
    var format: RecordingFormat {
        bar == .gif ? .gif : .mp4
    }
}

/// The recording's control bar (design, Control panel): for a GIF recording the `GIF` tag, then
/// the elapsed time, orange from the format's soft limit, then Stop and Cancel, each at its
/// `RecordingPanelLayout` frame.
struct RecordingPanelView: View {
    let model: RecordingPanelModel

    var body: some View {
        let bar = model.bar
        let size = RecordingPanelLayout.size(of: bar)
        ZStack(alignment: .topLeading) {
            if let tag = RecordingPanelLayout.tagFrame(of: bar) {
                Text("GIF")
                    .font(Font(RecordingPanelLayout.tagFont as CTFont))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, RecordingPanelLayout.tagPadding)
                    .padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.secondary, lineWidth: 1))
                    .placed(in: tag)
            }
            Text(RecordingClock.format(model.elapsed))
                .font(Font(RecordingPanelLayout.timeFont as CTFont))
                .foregroundStyle(RecordingClock.isPastSoftLimit(model.elapsed, format: model.format) ? Color.orange : Color.primary)
                .lineLimit(1)
                .placed(in: RecordingPanelLayout.timeFrame(of: bar), alignment: .leading)
            Button {
                model.onStop()
            } label: {
                Image(systemName: "stop.fill")
                    .foregroundStyle(.red)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Stop")
            .placed(in: RecordingPanelLayout.stopFrame(of: bar))
            Button {
                model.onCancel()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .help("Discard the recording")
            .accessibilityLabel("Cancel")
            .placed(in: RecordingPanelLayout.cancelFrame(of: bar))
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .buttonStyle(.borderless)
        .font(.system(size: 14, weight: .semibold))
        .disabled(!model.stopEnabled)
        .background(.regularMaterial, in: Capsule())
        .contentShape(Capsule())
        // The panel never becomes key, so the bar is dragged by this gesture as well as by
        // `isMovableByWindowBackground`.
        .gesture(WindowDragGesture())
    }
}

private extension View {
    /// Sizes the view to `frame` and puts it there, in the bar's top-left points.
    func placed(in frame: CGRect, alignment: Alignment = .center) -> some View {
        self.frame(width: frame.width, height: frame.height, alignment: alignment)
            .position(x: frame.midX, y: frame.midY)
    }
}
