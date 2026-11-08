import SwiftUI

/// Thumbnail, upload status with Copy URL, Retry and Save As…, Annotate and Delete, a hover Close
/// badge, and a context menu with every action. Hosted in `QuickAccessPanel`. A recording's card
/// shows its poster with a badge, opens it on a click, and has Copy File in place of Annotate,
/// Pin and Copy Image (recording design, Quick Access card). An MP4 adds `Trim…`, and `Upload
/// Trimmed` while its link is stale; one marked `Sound not muted` offers only Open, `Trim…` and
/// Delete (recording R2 design, Kind, Stale link and Privacy rule).
struct QuickAccessView: View {
    static let size = CGSize(width: 340, height: 104)

    let model: QuickAccessModel

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 4) {
                status
                buttonRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 8) {
                if model.showsImageActions {
                    Button {
                        model.actions.annotate(model.record.id)
                    } label: {
                        Image(systemName: "pencil.tip.crop.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Annotate")
                    .accessibilityLabel("Annotate")
                    Button {
                        model.actions.pin(model.record.id)
                    } label: {
                        Image(systemName: "pin")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Pin to screen")
                    .accessibilityLabel("Pin to screen")
                }
                Button {
                    model.actions.delete(model.record.id)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!model.canDelete)
                .help(model.record.isUploading ? "Cancel the upload and delete this capture" : "Delete this capture")
            }
        }
        .padding(12)
        .frame(width: Self.size.width, height: Self.size.height)
        // Under the content and over the material: a press anywhere but a button drags out. The
        // status texts do not take the pointer, so a failure's full message, or why a recording is
        // only kept in TidyShot, is this view's tooltip.
        .background(QuickAccessCardDragSource(model: model, toolTip: cardToolTip))
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.quaternary))
        .overlay(alignment: .topLeading) { closeBadge }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contextMenu { menuItems }
        .onHover { model.isHovered = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Close") { model.onClose() }
    }

    /// Shown while the pointer is over the card, as the macOS screenshot thumbnail does.
    @ViewBuilder
    private var closeBadge: some View {
        if model.isHovered {
            Button {
                model.onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Close")
            .accessibilityLabel("Close")
            .padding(4)
        }
    }

    @ViewBuilder
    private var menuItems: some View {
        Button("Copy URL") { model.actions.copy(model.record.id) }
            .disabled(model.record.linkURL == nil)
        if model.showsImageActions {
            Button("Copy Image") { model.actions.copyImage(model.record.id) }
        }
        if model.canCopyFile {
            Button("Copy File") { model.actions.copyFile(model.record.id) }
        }
        if model.canSaveAs {
            Button("Save As…") { model.actions.saveAs(model.record.id) }
        }
        if model.showsImageActions {
            Button("Annotate") { model.actions.annotate(model.record.id) }
            Button("Pin to Screen") { model.actions.pin(model.record.id) }
        }
        if model.trimState.showsTrim {
            Button("Trim…") { model.actions.trim(model.record.id) }
                .disabled(!model.trimState.canTrim)
        }
        if model.trimState.showsUploadTrimmed {
            Button("Upload Trimmed") { model.actions.uploadTrimmed(model.record.id) }
                .disabled(!model.trimState.canUploadTrimmed)
        }
        if model.canReveal {
            Button("Reveal in Finder") { model.actions.reveal(model.record.id) }
        }
        Divider()
        Button("Close") { model.onClose() }
        Button(CaptureDeletion.actionTitle(confirmBeforeDeleting: AppSettings.shared.confirmBeforeDeleting)) { model.actions.delete(model.record.id) }
            .disabled(!model.canDelete)
    }

    /// Copy URL or Retry when they apply, then Save As… in every state but `Sound not muted`. Retry
    /// is disabled while a Trim pass writes the file.
    private var buttonRow: some View {
        HStack(spacing: 6) {
            switch model.record.uploadState {
            case .uploaded:
                Button("Copy URL") { model.actions.copy(model.record.id) }
            case .failed:
                Button("Retry") { model.actions.retry(model.record.id) }
                    .disabled(!model.canRetry)
            case .uploading, .none:
                EmptyView()
            }
            if model.canSaveAs {
                Button("Save As…") { model.actions.saveAs(model.record.id) }
            }
        }
        .controlSize(.small)
    }

    @ViewBuilder
    private var thumbnail: some View {
        let image = Group {
            if let image = model.thumbnail {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: model.record.isTimeBased ? "film" : "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 96, height: 72)
        .background(Color.black.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .bottomTrailing) {
            if let badge = model.badge, model.thumbnail != nil {
                VideoBadge(badge: badge, duration: model.record.durationSeconds, fontSize: 10)
                    .padding(4)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        // A drag from the thumbnail drags out; a click without a drag reveals a save-folder file,
        // or opens a recording.
        let click = thumbnailClick
        image
            .allowsHitTesting(false)
            .overlay(QuickAccessCardDragSource(model: model, onClick: click?.action, toolTip: click?.toolTip))
    }

    /// What a click on the thumbnail does. A recording opens in its default app, or its link in
    /// the browser when only the upload is left; this replaces Reveal, which stays in the menu.
    private var thumbnailClick: (action: () -> Void, toolTip: String)? {
        if model.record.isTimeBased {
            return model.canOpen ? ({ model.actions.open(model.record.id) }, "Open") : nil
        }
        return model.canReveal ? ({ model.actions.reveal(model.record.id) }, "Reveal in Finder") : nil
    }

    /// The card's tooltip: a failed upload's or download's message, why a recording is only kept in
    /// TidyShot, or why its sound was not muted (`statusContent` may not have room for the whole text).
    private var cardToolTip: String? {
        switch model.status {
        case .failed(let message), .downloadFailed(let message): message
        case .kept: Self.keptText
        case .soundNotMuted: CaptureRecord.soundNotMutedBody
        default: nil
        }
    }

    static let keptText = "Not in your save folder. Use Save As… to keep a copy."

    /// The file name, or what stands in for it for an upload-only capture.
    private var fileLabel: String {
        model.record.fileURL?.lastPathComponent ?? "Upload only, no local file"
    }

    /// Labels and texts only, none of them hit-testable: a press on them reaches the card's drag
    /// surface (`QuickAccessCardDragSource`) in the background.
    private var status: some View {
        statusContent
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var statusContent: some View {
        switch model.status {
        case .uploading(let fraction):
            progressRow("Uploading…", fraction: fraction)
            detail(fileLabel)
        case .downloading(let fraction):
            progressRow("Downloading…", fraction: fraction)
            detail(fileLabel)
        case .optimizing:
            progressRow("Optimizing…", fraction: nil)
            detail(fileLabel)
        case .urlCopied(let url):
            headline("URL copied", symbol: "checkmark.circle.fill", tint: .green)
            detail(url.absoluteString, secondary: false)
        case .uploaded(let url):
            headline("Uploaded", symbol: "checkmark.circle.fill", tint: .green)
            detail(url.absoluteString, secondary: false)
        case .linkNotUpdated(let url):
            headline(RecentCaptureFormatting.linkNotUpdatedText, symbol: "exclamationmark.circle.fill", tint: .orange)
            detail(url.absoluteString, secondary: false)
        case .failed(let message):
            headline("Upload failed", symbol: "exclamationmark.triangle.fill", tint: .red)
            detail(message, truncation: .tail)
        case .downloadFailed:
            headline("Download failed", symbol: "exclamationmark.triangle.fill", tint: .red)
            detail(fileLabel)
        case .saved(let name):
            headline("Saved", symbol: "checkmark.circle.fill", tint: .green)
            detail(name)
        case .kept:
            headline("Kept in TidyShot", symbol: "exclamationmark.circle.fill", tint: .orange)
            detail(Self.keptText, lines: 2, truncation: .tail)
        case .soundNotMuted:
            headline(CaptureRecord.soundNotMutedTitle, symbol: "exclamationmark.triangle.fill", tint: .orange)
            detail(CaptureRecord.soundNotMutedBody, lines: 2, truncation: .tail)
        }
    }

    /// The state's title with its symbol, in the state's colour.
    private func headline(_ title: String, symbol: String, tint: Color) -> some View {
        Label(title, systemImage: symbol)
            .foregroundStyle(tint)
    }

    /// A small circular progress ring (indeterminate for nil) beside `title`.
    private func progressRow(_ title: String, fraction: Double?) -> some View {
        HStack(spacing: 8) {
            Group {
                if let fraction { ProgressView(value: fraction) } else { ProgressView() }
            }
            .progressViewStyle(.circular)
            .controlSize(.small)
            Text(title)
        }
    }

    /// A caption line under the headline: the file or the link, cut in the middle when it does not
    /// fit, or a message, which keeps its start.
    private func detail(_ text: String, secondary: Bool = true, lines: Int = 1,
                        truncation: Text.TruncationMode = .middle) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(secondary ? HierarchicalShapeStyle.secondary : .primary)
            .lineLimit(lines)
            .truncationMode(truncation)
    }
}

/// A recording's poster badge, in the corner of the card's and the row's thumbnail: `play.fill`
/// for an MP4 or `GIF` for a GIF, and the duration (`0:42`).
struct VideoBadge: View {
    let badge: RecentCaptureFormatting.RecordingBadge
    let duration: Double?
    let fontSize: CGFloat

    var body: some View {
        HStack(spacing: 2) {
            switch badge {
            case .play: Image(systemName: "play.fill")
            case .gif: Text("GIF")
            }
            if let duration {
                Text(RecordingClock.format(duration))
                    .monospacedDigit()
            }
        }
        .font(.system(size: fontSize, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(Color.black.opacity(0.6), in: Capsule())
    }
}
