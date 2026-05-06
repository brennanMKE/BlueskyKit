import SwiftUI
import BlueskyCore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A full post card: repost banner, author header, body text, optional embed, and action bar.
///
/// Supply an `Actions` value to handle taps; omit it for a read-only display (e.g. notifications).
public struct PostCard: View {

    let item: FeedViewPost
    var actions: Actions?

    @Environment(\.blueskyTheme) private var theme

    public init(item: FeedViewPost, actions: Actions? = nil) {
        self.item = item
        self.actions = actions
    }

    // MARK: - Actions

    public struct Actions {
        public var onTap: ((PostView) -> Void)?
        public var onAuthorTap: ((ProfileBasic) -> Void)?
        public var onReply: ((PostView) -> Void)?
        public var onRepost: ((PostView) -> Void)?
        public var onLike: ((PostView) -> Void)?
        public var onShare: ((PostView) -> Void)?
        public var onBookmark: ((PostView) -> Void)?
        public var onHashtagTap: ((String) -> Void)?
        public var onMore: ((PostView) -> Void)?
        /// Whether the viewer has bookmarked this post (drives the filled/unfilled icon).
        public var isBookmarked: Bool = false

        public init() {}
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let reason = item.reason {
                switch reason {
                case .repost(let by, _):
                    repostBanner(by: by)
                case .pin:
                    pinnedBanner
                case .unknown:
                    EmptyView()
                }
            }
            HStack(alignment: .top, spacing: Spacing.sm) {
                avatarColumn
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    // Content area: author header, post body, and optional embed.
                    // Wrapped in its own tappable region so the card-level tap
                    // does not extend over the action bar (which has its own buttons).
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        authorHeader
                        postBody
                        if let embed = item.post.embed {
                            embedView(for: embed)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        actions?.onTap?(item.post)
                    }
                    actionBar
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
        .background(theme.colors.background)
    }

    /// Render a post embed, with image embeds extended toward the card edge.
    ///
    /// Image embeds (single-image and grid) get a negative leading inset that
    /// cancels out the avatar column (`Spacing.md` outer + 44 avatar +
    /// `Spacing.sm` gap = 64) and a negative trailing inset that cancels the
    /// outer `Spacing.md` (= 12), then a small `Spacing.xs` (= 4) of breathing
    /// room on each side. Non-image embeds (link cards, quote posts, video)
    /// stay aligned with the body text.
    @ViewBuilder
    private func embedView(for embed: BlueskyCore.EmbedView) -> some View {
        if isImageOnlyEmbed(embed) {
            // Card-edge image embed — RN parity (#0076).
            // leading offset: -(avatar 44 + sm gap 8) + xs (4) = -48
            // trailing offset: 0 (we want the image to extend to the right card edge,
            // canceled by negative trailing padding equal to outer md)
            PostEmbedView(embed: embed)
                .padding(.leading, -(44 + Spacing.sm) + Spacing.xs)
                .padding(.trailing, -Spacing.md + Spacing.xs)
        } else {
            PostEmbedView(embed: embed)
        }
    }

    /// `true` for embeds where we want the card-edge image treatment:
    /// `images` and `recordWithMedia(images, …)` (the media half is what
    /// actually renders edge-to-edge; the quote half stays inset).
    private func isImageOnlyEmbed(_ embed: BlueskyCore.EmbedView) -> Bool {
        switch embed {
        case .images: return true
        default:      return false
        }
    }

    // MARK: - Subviews

    private var avatarColumn: some View {
        AvatarView(
            url: item.post.author.avatar,
            handle: item.post.author.handle.rawValue,
            size: 44
        )
        .onTapGesture { actions?.onAuthorTap?(item.post.author) }
    }

    private var authorHeader: some View {
        HStack(spacing: Spacing._2xs) {
            // Display name + verified badge + handle form a single tappable
            // region that navigates to the author's profile (issue #0046).
            // The surrounding content tap (which opens the thread) still
            // fires when the user taps elsewhere on the row.
            HStack(spacing: Spacing._2xs) {
                if let displayName = item.post.author.displayName, !displayName.isEmpty {
                    Text(displayName)
                        .font(Typography.headline)
                        .foregroundStyle(theme.colors.textPrimary)
                        .lineLimit(1)
                }
                if let badge = VerifiedBadge.forProfile(item.post.author) {
                    badge
                }
                Text("@\(item.post.author.handle.rawValue)")
                    .font(Typography.bodySmall)
                    .foregroundStyle(theme.colors.textTertiary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
            .onTapGesture { actions?.onAuthorTap?(item.post.author) }
            Spacer(minLength: 0)
            Text(RelativeTimeFormatter.string(from: item.post.indexedAt))
                .font(Typography.footnote)
                .foregroundStyle(theme.colors.textTertiary)
        }
    }

    private var postBody: some View {
        // Extracted to `PostBodyView` (#0079) so non-feed surfaces — notification
        // rows in particular — can reuse the same font, color, and facet handling.
        PostBodyView(
            text: item.post.record.text,
            facets: item.post.record.facets,
            onHashtagTap: { tag in actions?.onHashtagTap?(tag) }
        )
    }

    private var actionBar: some View {
        let post = item.post
        let isLiked = post.viewer?.like != nil
        let isReposted = post.viewer?.repost != nil

        // Order matches RN (#0076): comment · repost · like · bookmark · share · ellipsis.
        return HStack(spacing: Spacing.xl) {
            actionButton(
                icon: "bubble.left",
                count: post.replyCount,
                color: theme.colors.textTertiary,
                helpText: "Reply"
            ) { actions?.onReply?(post) }

            actionButton(
                icon: "arrow.2.squarepath",
                count: post.repostCount,
                color: isReposted ? theme.colors.success : theme.colors.textTertiary,
                helpText: "Repost"
            ) { actions?.onRepost?(post) }

            actionButton(
                icon: isLiked ? "heart.fill" : "heart",
                count: post.likeCount,
                color: isLiked ? theme.colors.like : theme.colors.textTertiary,
                helpText: "Like"
            ) { actions?.onLike?(post) }

            actionButton(
                icon: actions?.isBookmarked == true ? "bookmark.fill" : "bookmark",
                count: nil,
                color: actions?.isBookmarked == true ? theme.colors.link : theme.colors.textTertiary,
                helpText: actions?.isBookmarked == true ? "Remove Bookmark" : "Bookmark"
            ) { actions?.onBookmark?(post) }

            if let url = shareURL(for: post) {
                ShareLink(item: url) {
                    HStack(spacing: Spacing._2xs) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16))
                    }
                    .foregroundStyle(theme.colors.textTertiary)
                    .help("Share")
                }
                .buttonStyle(.plain)
            }

            Menu {
                Button {
                    let text = post.record.text
                    #if canImport(UIKit)
                    UIPasteboard.general.string = text
                    #elseif canImport(AppKit)
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(text, forType: .string)
                    #endif
                } label: {
                    Label("Copy post text", systemImage: "doc.on.doc")
                }

                Button {
                    actions?.onMore?(post)
                } label: {
                    Label("Mute thread", systemImage: "speaker.slash")
                }

                Divider()

                Button(role: .destructive) {
                    actions?.onMore?(post)
                } label: {
                    Label("Report post", systemImage: "flag")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16))
                    .foregroundStyle(theme.colors.textTertiary)
                    .help("More actions")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.borderless)

            Spacer(minLength: 0)
        }
        .padding(.top, Spacing._2xs)
    }

    private func shareURL(for post: PostView) -> URL? {
        let handle = post.author.handle.rawValue
        let rkey = post.uri.rawValue.components(separatedBy: "/").last ?? ""
        guard !rkey.isEmpty else { return nil }
        return URL(string: "https://bsky.app/profile/\(handle)/post/\(rkey)")
    }

    // MARK: - Helpers

    private func repostBanner(by profile: ProfileBasic) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "arrow.2.squarepath")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.colors.textTertiary)
            Text("Reposted by \(profile.displayName ?? profile.handle.rawValue)")
                .font(Typography.footnote)
                .foregroundStyle(theme.colors.textTertiary)
        }
        .padding(.horizontal, Spacing.md + 44 + Spacing.sm)
        .padding(.top, Spacing.xs)
    }

    /// "📌 Pinned" banner for the actor's pinned post on their Posts tab
    /// (#0087). Rendered above the byline in the same horizontal slot as the
    /// repost banner so the two never collide (the AT Proto feed never
    /// returns both reasons on the same item).
    private var pinnedBanner: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "pin.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.colors.textTertiary)
            Text("Pinned")
                .font(Typography.footnote)
                .foregroundStyle(theme.colors.textTertiary)
        }
        .padding(.horizontal, Spacing.md + 44 + Spacing.sm)
        .padding(.top, Spacing.xs)
    }

    private func actionButton(
        icon: String,
        count: Int?,
        color: Color,
        helpText: String = "",
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing._2xs) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                if let count, count > 0 {
                    Text(CompactNumberFormatter.string(from: count))
                        .font(Typography.footnote)
                }
            }
            .foregroundStyle(color)
            .help(helpText)
        }
        .buttonStyle(.plain)
    }

}

#Preview("PostCard - Light") {
    let author = ProfileBasic(
        did: DID(rawValue: "did:plc:alice"),
        handle: Handle(rawValue: "alice.bsky.social"),
        displayName: "Alice",
        avatar: nil,
        verification: VerificationState(verifiedStatus: "valid", trustedVerifierStatus: "none")
    )
    let record = PostRecord(
        text: "Hello Bluesky! Check out #bluesky — the open social network.",
        createdAt: Date(timeIntervalSinceNow: -120)
    )
    let post = PostView(
        uri: ATURI(rawValue: "at://did:plc:alice/app.bsky.feed.post/abc"),
        cid: "bafyabc",
        author: author,
        record: record,
        embed: nil,
        replyCount: 3,
        repostCount: 12,
        likeCount: 47,
        quoteCount: 2,
        indexedAt: Date(timeIntervalSinceNow: -120),
        viewer: nil
    )
    let item = FeedViewPost(post: post, reply: nil, reason: nil)

    ScrollView {
        PostCard(item: item, actions: PostCard.Actions())
        Divider()
    }
    .frame(maxWidth: .infinity)
    .background(.background)
    .blueskyTheme(.light)
    .preferredColorScheme(.light)
}

#Preview("PostCard — Dark") {
    let author = ProfileBasic(
        did: DID(rawValue: "did:plc:alice"),
        handle: Handle(rawValue: "alice.bsky.social"),
        displayName: "Alice",
        avatar: nil,
        verification: VerificationState(verifiedStatus: "valid", trustedVerifierStatus: "none")
    )
    let record = PostRecord(
        text: "Hello Bluesky! Check out #bluesky — the open social network.",
        createdAt: Date(timeIntervalSinceNow: -120)
    )
    let post = PostView(
        uri: ATURI(rawValue: "at://did:plc:alice/app.bsky.feed.post/abc"),
        cid: "bafyabc",
        author: author,
        record: record,
        embed: nil,
        replyCount: 3,
        repostCount: 12,
        likeCount: 47,
        quoteCount: 2,
        indexedAt: Date(timeIntervalSinceNow: -120),
        viewer: nil
    )
    let item = FeedViewPost(post: post, reply: nil, reason: nil)

    ScrollView {
        PostCard(item: item, actions: PostCard.Actions())
        Divider()
    }
    .frame(maxWidth: .infinity)
    .background(.background)
    .blueskyTheme(.dark)
    .preferredColorScheme(.dark)
}
