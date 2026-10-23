import SwiftUI

/// Thumbnail, upload status with Copy URL, Retry and Save As…, Annotate and Delete, a hover Close
/// badge, and a context menu with every action. Hosted in `QuickAccessPanel`. A recording's card
/// shows its poster with a badge, opens it on a click, and has Copy File in place of Annotate,
/// Pin and Copy Image (recording design, Quick Access card).
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
                        model.onAnnotate()
                    } label: {
                        Image(systemName: "pencil.tip.crop.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Annotate")
                    .accessibilityLabel("Annotate")
                    Button {
                        model.onPin()
                    } label: {
                        Image(systemName: "pin")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Pin to screen")
                    .accessibilityLabel("Pin to screen")
                }
                Button {
                    model.onDelete()
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
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
        Button("Copy URL") { model.onCopy() }
            .disabled(model.record.linkURL == nil)
        if model.showsImageActions {
            Button("Copy Image") { model.onCopyImage() }
        }
        if model.canCopyFile {
            Button("Copy File") { model.onCopyFile() }
        }
        Button("Save As…") { model.onSaveAs() }
        if model.showsImageActions {
            Button("Annotate") { model.onAnnotate() }
            Button("Pin to Screen") { model.onPin() }
        }
        if model.canReveal {
            Button("Reveal in Finder") { model.onReveal() }
        }
        Divider()
        Button("Close") { model.onClose() }
        Button(CaptureDeletion.actionTitle(confirmBeforeDeleting: AppSettings.shared.confirmBeforeDeleting)) { model.onDelete() }
    }

    /// Copy URL or Retry when they apply, then Save As… in every state.
    private var buttonRow: some View {
        HStack(spacing: 6) {
            switch model.record.uploadState {
            case .uploaded:
                Button("Copy URL") { model.onCopy() }
            case .failed:
                Button("Retry") { model.onRetry() }
            case .uploading, .none:
                EmptyView()
            }
            Button("Save As…") { model.onSaveAs() }
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
            if model.record.isTimeBased, model.thumbnail != nil {
                VideoBadge(duration: model.record.durationSeconds, fontSize: 10)
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
            guard model.record.hasLocalFile || model.record.linkURL != nil else { return nil }
            return ({ model.onOpen() }, "Open")
        }
        return model.canReveal ? ({ model.onReveal() }, "Reveal in Finder") : nil
    }

    /// The card's tooltip: a failed upload's message, or why a recording is only kept in TidyShot
    /// (`statusContent` may not have room for all of either).
    private var cardToolTip: String? {
        switch model.status {
        case .failed(let message): message
        case .kept: Self.keptText
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
            HStack(spacing: 8) {
                ProgressView(value: fraction)
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                Text("Uploading…")
            }
            Text(fileLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        case .optimizing:
            HStack(spacing: 8) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                Text("Optimizing…")
            }
            Text(fileLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        case .urlCopied(let url):
            Label("URL copied", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(url.absoluteString)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
        case .uploaded(let url):
            Label("Uploaded", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(url.absoluteString)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
        case .failed(let message):
            Label("Upload failed", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        case .saved(let name):
            Label("Saved", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(name)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        case .kept:
            Label("Kept in TidyShot", systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
            Text(Self.keptText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}

/// A recording's poster badge, in the corner of the card's and the row's thumbnail: `play.fill`
/// and the duration (`0:42`).
struct VideoBadge: View {
    let duration: Double?
    let fontSize: CGFloat

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "play.fill")
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
