import SwiftUI
import BlueskyCore

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

        public init() {}
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let reason = item.reason, case .repost(let by, _) = reason {
                repostBanner(by: by)
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
                            PostEmbedView(embed: embed)
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
            if let displayName = item.post.author.displayName, !displayName.isEmpty {
                Text(displayName)
                    .font(Typography.headline)
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(1)
            }
            Text("@\(item.post.author.handle.rawValue)")
                .font(Typography.bodySmall)
                .foregroundStyle(theme.colors.textTertiary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(relativeTimestamp(item.post.indexedAt))
                .font(Typography.footnote)
                .foregroundStyle(theme.colors.textTertiary)
        }
    }

    private var postBody: some View {
        RichTextView(
            text: item.post.record.text,
            facets: item.post.record.facets,
            foregroundColor: theme.colors.textPrimary,
            linkColor: theme.colors.link
        )
    }

    private var actionBar: some View {
        let post = item.post
        let isLiked = post.viewer?.like != nil
        let isReposted = post.viewer?.repost != nil

        return HStack(spacing: Spacing.xl) {
            actionButton(
                icon: "bubble.left",
                count: post.replyCount,
                color: theme.colors.textTertiary
            ) { actions?.onReply?(post) }

            actionButton(
                icon: "arrow.2.squarepath",
                count: post.repostCount,
                color: isReposted ? theme.colors.success : theme.colors.textTertiary
            ) { actions?.onRepost?(post) }

            actionButton(
                icon: isLiked ? "heart.fill" : "heart",
                count: post.likeCount,
                color: isLiked ? theme.colors.like : theme.colors.textTertiary
            ) { actions?.onLike?(post) }

            if let url = shareURL(for: post) {
                ShareLink(item: url) {
                    HStack(spacing: Spacing._2xs) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16))
                    }
                    .foregroundStyle(theme.colors.textTertiary)
                }
                .buttonStyle(.plain)
            }

            actionButton(
                icon: "bookmark",
                count: nil,
                color: theme.colors.textTertiary
            ) { actions?.onBookmark?(post) }

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

    private func actionButton(
        icon: String,
        count: Int?,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing._2xs) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                if let count, count > 0 {
                    Text(abbreviate(count))
                        .font(Typography.footnote)
                }
            }
            .foregroundStyle(color)
        }
        .buttonStyle(.plain)
    }

    private func relativeTimestamp(_ date: Date) -> String {
        let secs = Int(Date.now.timeIntervalSince(date))
        if secs < 60  { return "\(secs)s" }
        if secs < 3600 { return "\(secs / 60)m" }
        if secs < 86400 { return "\(secs / 3600)h" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private func abbreviate(_ n: Int) -> String {
        if n < 1000  { return "\(n)" }
        if n < 10000 { return String(format: "%.1fK", Double(n) / 1000) }
        return "\(n / 1000)K"
    }
}

#Preview("PostCard") {
    let author = ProfileBasic(
        did: DID(rawValue: "did:plc:alice"),
        handle: Handle(rawValue: "alice.bsky.social"),
        displayName: "Alice",
        avatar: nil
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
    .blueskyTheme(.light)
}
