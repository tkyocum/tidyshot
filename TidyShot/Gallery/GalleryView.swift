import SwiftUI

/// What the gallery's cells and preview pane can do with a capture. All run on the coordinator.
struct GalleryActions {
    /// Copies the public URL, or the local file when the capture was never uploaded.
    var copy: (UUID) -> Void
    var retry: (UUID) -> Void
    var reveal: (UUID) -> Void
    /// Deletes everywhere after one confirmation.
    var delete: (UUID) -> Void
}

/// Grid of thumbnails, newest first, with a preview pane for the hovered capture.
struct GalleryView: View {
    static let minimumSize = CGSize(width: 820, height: 520)

    let model: GalleryModel
    let actions: GalleryActions

    var body: some View {
        HStack(spacing: 0) {
            if model.records.isEmpty {
                ContentUnavailableView("No captures yet", systemImage: "photo.on.rectangle",
                                       description: Text("Captures appear here newest first."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 12)], spacing: 12) {
                        ForEach(model.records) { record in
                            GalleryCell(record: record, model: model, isHovered: model.hoveredID == record.id, actions: actions)
                                .onHover { inside in
                                    if inside { model.hover(record.id) }
                                }
                        }
                    }
                    .padding(16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            GalleryPreviewPane(record: model.previewRecord, image: model.preview, actions: actions)
                .frame(width: 320)
        }
        .frame(minWidth: Self.minimumSize.width, minHeight: Self.minimumSize.height)
        // Runs on appear and again whenever the previewed record changes; SwiftUI cancels the
        // previous load.
        .task(id: model.previewRecord?.id) { await model.loadPreview() }
    }
}

/// What a cell's thumbnail depends on: the record, and its stored thumbnail, which a capture
/// gets a moment after its cell may already be on screen.
private struct ThumbnailKey: Hashable {
    let id: UUID
    let fileName: String?
}

/// One thumbnail with a status badge. Click copies; the context menu has everything else.
struct GalleryCell: View {
    let record: CaptureRecord
    let model: GalleryModel
    let isHovered: Bool
    let actions: GalleryActions
    /// Loaded by the `.task` below, never in `body`.
    @State private var thumbnail: NSImage?

    /// The object's or file's name, shown under the date and read by VoiceOver.
    private var displayName: String {
        record.uploadedURL?.lastPathComponent ?? record.fileURL?.lastPathComponent ?? record.appName ?? "Capture"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 120)
                .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                GalleryStatusBadge(state: record.uploadState)
                    .padding(6)
            }
            Text(record.timestamp.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
            Text(displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(8)
        .background(isHovered ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture { actions.copy(record.id) }
        .contextMenu { GalleryMenuItems(record: record, actions: actions) }
        .help(record.uploadedURL != nil ? "Click to copy the URL" : record.hasLocalFile ? "Click to copy the file" : "")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(GalleryStatusBadge.title(for: record.uploadState)), \(record.timestamp.formatted(date: .abbreviated, time: .shortened)), \(displayName)")
        .task(id: ThumbnailKey(id: record.id, fileName: record.thumbnailFileName)) {
            thumbnail = await model.thumbnail(for: record)
        }
    }
}

/// `Uploaded`, `Uploading`, `Failed` or `Saved`, as a small capsule on the thumbnail.
struct GalleryStatusBadge: View {
    let state: CaptureRecord.UploadState

    static func title(for state: CaptureRecord.UploadState) -> String {
        switch state {
        case .none: "Saved"
        case .uploading: "Uploading"
        case .uploaded: "Uploaded"
        case .failed: "Failed"
        }
    }

    var body: some View {
        Text(Self.title(for: state))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.9), in: Capsule())
            .foregroundStyle(.white)
    }

    private var color: Color {
        switch state {
        case .none: .gray
        case .uploading: .blue
        case .uploaded: .green
        case .failed: .red
        }
    }
}

/// Shared by the cell's context menu and the preview pane's buttons.
struct GalleryMenuItems: View {
    let record: CaptureRecord
    let actions: GalleryActions

    var body: some View {
        if record.uploadedURL != nil {
            Button("Copy URL") { actions.copy(record.id) }
        } else if record.hasLocalFile {
            Button("Copy File") { actions.copy(record.id) }
        }
        if record.isFailed {
            Button("Retry Upload") { actions.retry(record.id) }
        }
        if record.hasLocalFile {
            Button("Reveal in Finder") { actions.reveal(record.id) }
        }
        Divider()
        Button("Delete…", role: .destructive) { actions.delete(record.id) }
    }
}

/// The hovered capture, larger, with its details and actions.
struct GalleryPreviewPane: View {
    let record: CaptureRecord?
    let image: NSImage?
    let actions: GalleryActions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let record {
                Group {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                Text(record.timestamp.formatted(date: .long, time: .standard))
                    .font(.headline)
                Text("\(record.pixelWidth) × \(record.pixelHeight) px" + (record.appName.map { "  ·  \($0)" } ?? ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                statusLine(for: record)
                if let fileURL = record.fileURL {
                    Text(record.fileIsTemporary ? "Temporary file, deleted after upload" : fileURL.path(percentEncoded: false))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                } else {
                    Text("No local file")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    GalleryMenuItems(record: record, actions: actions)
                }
                .controlSize(.small)
                Spacer()
            } else {
                Spacer()
                Text("Hover a capture to preview it.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private func statusLine(for record: CaptureRecord) -> some View {
        switch record.uploadState {
        case .uploaded(let url, _):
            Text(url.absoluteString)
                .font(.caption)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
        case .uploading(let fraction):
            ProgressView(value: fraction) { Text("Uploading…") }
                .controlSize(.small)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(3)
        case .none:
            Label("Saved locally, not uploaded", systemImage: "checkmark.circle")
                .font(.caption)
        }
    }
}
