import SwiftUI

/// Thumbnail, upload status, and a copy or retry button. Hosted in `QuickAccessPanel`.
struct QuickAccessView: View {
    static let size = CGSize(width: 340, height: 104)

    let model: QuickAccessModel

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 6) {
                status
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                model.onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(12)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.quaternary))
        .onHover { model.isHovered = $0 }
    }

    @ViewBuilder
    private var thumbnail: some View {
        Group {
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
        .onTapGesture { model.onReveal() }
        .help("Reveal in Finder")
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
            Text(model.record.fileURL.lastPathComponent)
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
            Button("Copy URL") { model.onCopy() }
                .controlSize(.small)
        case .failed(let message):
            Label("Upload failed", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Button("Retry") { model.onRetry() }
                .controlSize(.small)
        case .none:
            Label("Saved", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(model.record.fileURL.lastPathComponent)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
