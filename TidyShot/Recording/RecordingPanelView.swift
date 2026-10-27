import Observation
import SwiftUI

/// What the recording panel shows, and what its buttons call.
@Observable
final class RecordingPanelModel {
    /// Seconds since the first frame.
    var elapsed: TimeInterval = 0
    /// False once the recording is ending: Stop, Cancel and the mute button then do nothing.
    var stopEnabled = true
    /// Set at `show`, before the panel is laid out.
    var bar: RecordingPanelLayout.Bar = .plain
    /// Whether the sound is muted, as the controller says.
    var isMuted = false
    /// The R3 buttons, which only an area or fullscreen recording's bar has.
    var highlights = BarToggle(isOn: false, isEnabled: true, disabledToolTip: nil)
    var bubble = BarToggle(isOn: false, isEnabled: true, disabledToolTip: nil)
    @ObservationIgnored var onStop: () -> Void = {}
    @ObservationIgnored var onCancel: () -> Void = {}
    @ObservationIgnored var onMute: () -> Void = {}
    @ObservationIgnored var onHighlights: () -> Void = {}
    @ObservationIgnored var onBubble: () -> Void = {}

    /// The mute button's symbol shows the state; its tool tip and label say what a press does.
    var muteSymbol: String {
        isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
    }

    var muteToolTip: String {
        isMuted ? "Unmute the sound" : "Mute the sound"
    }

    var muteAccessibilityLabel: String {
        isMuted ? "Unmute" : "Mute"
    }

    /// The R3 buttons, like the mute button: the symbol shows the state, and the tool tip and the
    /// label say what a press does. A disabled button's tool tip says why instead.
    var highlightsSymbol: String {
        highlights.isOn ? "cursorarrow.rays" : "cursorarrow"
    }

    var highlightsToolTip: String {
        Self.disabledToolTip(of: highlights) ?? highlightsAccessibilityLabel
    }

    var highlightsAccessibilityLabel: String {
        highlights.isOn ? "Stop highlighting clicks" : "Highlight clicks"
    }

    var bubbleSymbol: String {
        bubble.isOn ? "video.fill" : "video.slash.fill"
    }

    var bubbleToolTip: String {
        Self.disabledToolTip(of: bubble) ?? (bubble.isOn ? "Hide the webcam bubble" : "Show the webcam bubble")
    }

    var bubbleAccessibilityLabel: String {
        bubble.isOn ? "Hide webcam bubble" : "Show webcam bubble"
    }

    private static func disabledToolTip(of toggle: BarToggle) -> String? {
        toggle.isEnabled ? nil : toggle.disabledToolTip
    }

    /// The recording's format, for the soft limit: only a GIF recording's bar has the tag.
    var format: RecordingFormat {
        bar.showsTag ? .gif : .mp4
    }
}

/// The recording's control bar (design, Control panel; R3 design, Bar): for a GIF recording the
/// `GIF` tag, then the elapsed time, orange from the format's soft limit, then for an area or
/// fullscreen recording the highlights and bubble buttons, then the mute button on a bar with it,
/// Stop and Cancel, each at its `RecordingPanelLayout` frame.
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
            if let highlights = RecordingPanelLayout.highlightsFrame(of: bar) {
                Button {
                    model.onHighlights()
                } label: {
                    Image(systemName: model.highlightsSymbol)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .help(model.highlightsToolTip)
                .accessibilityLabel(model.highlightsAccessibilityLabel)
                .disabled(!model.highlights.isEnabled)
                .placed(in: highlights)
            }
            if let bubble = RecordingPanelLayout.bubbleFrame(of: bar) {
                Button {
                    model.onBubble()
                } label: {
                    Image(systemName: model.bubbleSymbol)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .help(model.bubbleToolTip)
                .accessibilityLabel(model.bubbleAccessibilityLabel)
                .disabled(!model.bubble.isEnabled)
                .placed(in: bubble)
            }
            if let mute = RecordingPanelLayout.muteFrame(of: bar) {
                Button {
                    model.onMute()
                } label: {
                    Image(systemName: model.muteSymbol)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .help(model.muteToolTip)
                .accessibilityLabel(model.muteAccessibilityLabel)
                .placed(in: mute)
            }
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
