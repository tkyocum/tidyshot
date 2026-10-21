import SwiftUI

/// Thumbnail, upload status with Copy URL, Retry and Save As…, Annotate and Delete, a hover Close
/// badge, and a context menu with every action. Hosted in `QuickAccessPanel`.
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.quaternary))
        .overlay(alignment: .topLeading) { closeBadge }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contextMenu { menuItems }
        .onHover { model.isHovered = $0 }
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
        Button("Copy Image") { model.onCopyImage() }
        Button("Save As…") { model.onSaveAs() }
        Button("Annotate") { model.onAnnotate() }
        if model.canReveal {
            Button("Reveal in Finder") { model.onReveal() }
        }
        Divider()
        Button("Close") { model.onClose() }
        Button("Delete…") { model.onDelete() }
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
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 96, height: 72)
        .background(Color.black.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        if model.canReveal {
            image
                .onTapGesture { model.onReveal() }
                .help("Reveal in Finder")
        } else {
            image
        }
    }

    /// The file name, or what stands in for it for an upload-only capture.
    private var fileLabel: String {
        model.record.fileURL?.lastPathComponent ?? "Upload only, no local file"
    }

    @ViewBuilder
    private var status: some View {
        switch model.record.uploadState {
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
        case .uploaded(let url, _):
            Label("URL copied", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(url.absoluteString)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        case .failed(let message):
            Label("Upload failed", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(message)
        case .none:
            Label("Saved", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(fileLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
