import SwiftUI

/// What a Recent Captures row's buttons do. `RecentCapturesMenu` makes each one close the menu first.
struct RecentCaptureActions {
    /// Clicking the row: the URL, or the file when the capture was never uploaded.
    var copyLinkOrFile: (UUID) -> Void
    var copyLink: (UUID) -> Void
    var copyImage: (UUID) -> Void
    /// The overlay's delete: one confirmation, then storage, file, thumbnail and record.
    var delete: (UUID) -> Void
}

/// Hover state of one row, set from AppKit by `RecentCaptureMenuItemView`.
@Observable
final class RecentCaptureRowState {
    var isHighlighted = false
}

/// One row of the Recent Captures submenu: thumbnail, name, relative time, and Copy URL, Copy
/// Image and Delete buttons. Every string and flag is worked out before the row is built, and the
/// thumbnail loads in `.task`, so `body` does no work.
struct RecentCaptureRow: View {
    static let size = CGSize(width: 360, height: 52)
    static let thumbnailSize = CGSize(width: 56, height: 42)
    static let horizontalPadding: CGFloat = 14
    /// Where the thumbnail sits, in the item view's coordinates. The row is symmetric top to
    /// bottom, so AppKit's bottom-left origin gives the same rect.
    static let thumbnailFrame = CGRect(x: horizontalPadding, y: (size.height - thumbnailSize.height) / 2,
                                       width: thumbnailSize.width, height: thumbnailSize.height)

    let record: CaptureRecord
    let name: String
    let detail: String
    let canCopyLink: Bool
    let canCopyImage: Bool
    let state: RecentCaptureRowState
    let provider: ThumbnailProvider
    let actions: RecentCaptureActions
    @State private var thumbnail: NSImage?

    var body: some View {
        HStack(spacing: 4) {
            Button { actions.copyLinkOrFile(record.id) } label: {
                HStack(spacing: 10) {
                    thumbnailView
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(name), \(detail)")
            .accessibilityHint(canCopyLink ? "Copies the link" : "Copies the file")
            iconButton("link", label: "Copy URL", enabled: canCopyLink) { actions.copyLink(record.id) }
            iconButton("photo.on.rectangle", label: "Copy Image", enabled: canCopyImage) { actions.copyImage(record.id) }
            iconButton("trash", label: "Delete…", enabled: true) { actions.delete(record.id) }
        }
        .padding(.horizontal, Self.horizontalPadding)
        .frame(width: Self.size.width, height: Self.size.height)
        .background {
            if state.isHighlighted {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.08))
                    .padding(.horizontal, 5)
            }
        }
        .task(id: record.thumbnailFileName) {
            thumbnail = await provider.thumbnail(for: record)
        }
    }

    private var thumbnailView: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: Self.thumbnailSize.width, height: Self.thumbnailSize.height)
        .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func iconButton(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(!enabled)
        .help(label)
        .accessibilityLabel(label)
    }
}
