import SwiftUI
import BlueskyCore

/// Renders the resolved `EmbedView` attached to a post.
///
/// Handles all embed types: image grids, link cards, quote posts, video thumbnails,
/// and the recordWithMedia compound case. Callers supply navigation callbacks.
public struct PostEmbedView: View {

    let embed: BlueskyCore.EmbedView
    var onLinkTap: (URL) -> Void
    var onRecordTap: (ATURI) -> Void

    @Environment(\.blueskyTheme) private var theme

    public init(
        embed: BlueskyCore.EmbedView,
        onLinkTap: @escaping (URL) -> Void = { _ in },
        onRecordTap: @escaping (ATURI) -> Void = { _ in }
    ) {
        self.embed = embed
        self.onLinkTap = onLinkTap
        self.onRecordTap = onRecordTap
    }

    // MARK: - Body

    public var body: some View {
        switch embed {
        case .images(let images):
            imageGrid(images)
        case .external(let ext):
            linkCard(ext)
        case .record(let rv):
            quotePost(rv.record)
        case .recordWithMedia(let rv, let media):
            // The media part of recordWithMedia is always images or external.
            // AnyView erases the concrete type so both branches compile.
            VStack(alignment: .leading, spacing: Spacing.sm) {
                mediaOnlyEmbed(media)
                quotePost(rv.record)
            }
        case .video(let video):
            videoThumbnail(video)
        case .unknown:
            EmptyView()
        }
    }

    // MARK: - Media-only sub-embed (used inside recordWithMedia)

    /// Renders images or a link card — the two media types that can appear inside
    /// `recordWithMedia`.  Returns `AnyView` to break the type-erasure requirement
    /// for the `recordWithMedia` branch which cannot recurse through `body`.
    private func mediaOnlyEmbed(_ embed: BlueskyCore.EmbedView) -> AnyView {
        switch embed {
        case .images(let images): return AnyView(imageGrid(images))
        case .external(let ext):  return AnyView(linkCard(ext))
        default:                  return AnyView(EmptyView())
        }
    }

    // MARK: - Image grid

    @ViewBuilder
    private func imageGrid(_ images: [EmbedImageView]) -> some View {
        let capped = Array(images.prefix(4))
        if capped.count == 1 {
            singleImage(capped[0])
        } else {
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 2
            ) {
                ForEach(Array(capped.enumerated()), id: \.offset) { _, img in
                    AsyncImage(url: img.thumb) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Color.gray.opacity(0.2)
                        }
                    }
                    .frame(height: 120)
                    .clipped()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func singleImage(_ image: EmbedImageView) -> some View {
        AsyncImage(url: image.thumb) { phase in
            if let img = phase.image {
                img.resizable().aspectRatio(contentMode: .fit)
            } else {
                Color.gray.opacity(0.2).frame(height: 200)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel(image.alt)
    }

    // MARK: - Link card

    private func linkCard(_ ext: EmbedExternalView) -> some View {
        Button {
            if let url = URL(string: ext.uri) { onLinkTap(url) }
        } label: {
            HStack(alignment: .top, spacing: Spacing.sm) {
                if let thumb = ext.thumb {
                    AsyncImage(url: thumb) { phase in
                        if let img = phase.image {
                            img.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Color.gray.opacity(0.2)
                        }
                    }
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                VStack(alignment: .leading, spacing: Spacing._2xs) {
                    Text(ext.title)
                        .font(Typography.bodySmall)
                        .fontWeight(.medium)
                        .foregroundStyle(theme.colors.textPrimary)
                        .lineLimit(2)
                    if !ext.description.isEmpty {
                        Text(ext.description)
                            .font(Typography.footnote)
                            .foregroundStyle(theme.colors.textSecondary)
                            .lineLimit(2)
                    }
                    Text(ext.uri)
                        .font(Typography.footnote)
                        .foregroundStyle(theme.colors.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(Spacing.sm)
            .background(theme.colors.backgroundSecondary)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(theme.colors.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Quote post

    @ViewBuilder
    private func quotePost(_ content: EmbedRecordContent) -> some View {
        switch content {
        case .post(let record):
            Button { onRecordTap(record.uri) } label: {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(spacing: Spacing.xs) {
                        AvatarView(
                            url: record.author.avatar,
                            handle: record.author.handle.rawValue,
                            size: 20
                        )
                        Text(record.author.displayName ?? record.author.handle.rawValue)
                            .font(Typography.bodySmall)
                            .fontWeight(.medium)
                            .foregroundStyle(theme.colors.textPrimary)
                        Text("@\(record.author.handle.rawValue)")
                            .font(Typography.footnote)
                            .foregroundStyle(theme.colors.textTertiary)
                            .lineLimit(1)
                    }
                    Text(record.value.text)
                        .font(Typography.bodySmall)
                        .foregroundStyle(theme.colors.textSecondary)
                        .lineLimit(4)
                }
                .padding(Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.colors.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(theme.colors.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

        case .notFound:
            notAvailablePlaceholder("Post not found")
        case .blocked:
            notAvailablePlaceholder("Blocked post")
        case .unknown:
            EmptyView()
        }
    }

    // MARK: - Video thumbnail

    private func videoThumbnail(_ video: EmbedVideoView) -> some View {
        ZStack {
            if let thumb = video.thumbnail {
                AsyncImage(url: thumb) { phase in
                    if let img = phase.image {
                        img.resizable().aspectRatio(contentMode: .fit)
                    } else {
                        Color.black.opacity(0.1)
                    }
                }
            } else {
                Color.black.opacity(0.1)
            }
            Image(systemName: "play.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.9))
                .shadow(radius: 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .frame(maxHeight: 280)
    }

    // MARK: - Placeholder

    private func notAvailablePlaceholder(_ message: String) -> some View {
        Text(message)
            .font(Typography.footnote)
            .foregroundStyle(theme.colors.textTertiary)
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
