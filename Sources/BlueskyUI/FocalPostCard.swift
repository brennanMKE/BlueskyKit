import SwiftUI
import BlueskyCore
import Translation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The focal-post variant of `PostCard`: rendered for the post that the
/// user navigated to in `ThreadView`. Visually distinct from the default
/// `PostCard` so the viewer can see at a glance which post anchored the
/// thread (#0146).
///
/// Differences from `PostCard`, mirroring RN's
/// `screens/PostThread/components/ThreadItemAnchor.tsx`:
///
/// - **Larger avatar** (42pt — RN's `LINEAR_AVI_WIDTH`).
/// - **Larger display-name + handle** typography (RN's `text_lg`).
/// - **Body text uses `bodyLarge`** and bypasses the long-post clamp by
///   passing `isFocal: true` to `PostBodyView` (#0142).
/// - **Full timestamp** subtitle (`time · date`) below the body — RN's
///   `niceDate(i18n, indexedAt, 'dot separated')` format.
/// - **"Who can reply" badge** when a threadgate is set, reflecting the
///   active `allow` rules.
/// - **Tappable stat row** above the action bar: "X likes · Y reposts ·
///   Z quotes". Each fires a callback so the parent view can push the
///   destinations from #0139.
/// - More vertical padding around the card.
///
/// Action-bar parity with `PostCard` is intentional — the focal post
/// still needs Reply / Repost / Like / Bookmark / Share / More with the
/// same icons and tap targets.
public struct FocalPostCard: View {

    let item: FeedViewPost
    var actions: PostCard.Actions?

    /// "Who can reply" rules attached to this post's threadgate, when
    /// the AT Proto response includes one. Drives the small
    /// "Who can reply" badge above the body. `nil` (vs an empty array)
    /// means "no threadgate set" → the badge is hidden.
    let threadgateAllow: [ThreadgateAllowRule]?

    /// Tap on the "X likes" stat row.
    var onLikedByTap: ((ATURI) -> Void)?
    /// Tap on the "Y reposts" stat row.
    var onRepostedByTap: ((ATURI) -> Void)?
    /// Tap on the "Z quotes" stat row.
    var onQuotesTap: ((ATURI) -> Void)?

    @Environment(\.blueskyTheme) private var theme
    @Environment(\.openURL) private var openURL

    /// Toggles the system Translation popover for the focal-post body
    /// (#0143). Same pattern as `PostCard.isTranslating`.
    @State private var isTranslating: Bool = false

    /// "Copy link to post" → brief in-card toast (#0144).
    @State private var showCopiedToast: Bool = false

    public init(
        item: FeedViewPost,
        actions: PostCard.Actions? = nil,
        threadgateAllow: [ThreadgateAllowRule]? = nil,
        onLikedByTap: ((ATURI) -> Void)? = nil,
        onRepostedByTap: ((ATURI) -> Void)? = nil,
        onQuotesTap: ((ATURI) -> Void)? = nil
    ) {
        self.item = item
        self.actions = actions
        self.threadgateAllow = threadgateAllow
        self.onLikedByTap = onLikedByTap
        self.onRepostedByTap = onRepostedByTap
        self.onQuotesTap = onQuotesTap
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            authorRow
            contentBlock
            timestampSubtitle
            if hasEngagement {
                statRow
                    .padding(.top, Spacing.xs)
            }
            actionBar
                .padding(.top, Spacing.xs)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.lg)
        .background(theme.colors.background)
        // UI-test coupling surface (#0177): identifies the focal (anchor) post
        // row so the thread-view suite can assert it rendered and scope the
        // action-bar lookups to it. `children: .contain` keeps the nested
        // action buttons individually addressable.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("thread-focal-post")
        .translationPresentation(isPresented: $isTranslating, text: item.post.record.text)
        .toast(isPresented: $showCopiedToast, message: "Copied to clipboard")
    }

    // MARK: - Subviews

    /// Avatar (42pt) + display name (text_lg, semibold) + handle (text_md).
    /// Mirrors the RN top row in `ThreadItemAnchor`.
    private var authorRow: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            AvatarView(
                url: item.post.author.avatar,
                handle: item.post.author.handle.rawValue,
                size: 42
            )
            .onTapGesture { actions?.onAuthorTap?(item.post.author) }

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Spacing._2xs) {
                    if let displayName = item.post.author.displayName, !displayName.isEmpty {
                        Text(displayName)
                            .font(Typography.font(Typography.lg, weight: .semibold))
                            .foregroundStyle(theme.colors.textPrimary)
                            .lineLimit(1)
                    }
                    if let badge = VerifiedBadge.forProfile(item.post.author) {
                        badge
                    }
                }
                Text("@\(item.post.author.handle.rawValue)")
                    .font(Typography.body)
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
            .onTapGesture { actions?.onAuthorTap?(item.post.author) }

            Spacer(minLength: 0)
        }
    }

    /// Body text + optional embed. Body uses `bodyLarge` via
    /// `PostBodyView(isFocal: true)` so the focal post never clamps —
    /// RN passes `a.text_lg` and renders the full body.
    private var contentBlock: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            PostBodyView(
                text: item.post.record.text,
                facets: item.post.record.facets,
                isFocal: true,
                onHashtagTap: { tag in actions?.onHashtagTap?(tag) }
            )
            .font(Typography.bodyLarge)
            if let embed = item.post.embed {
                PostEmbedView(embed: embed)
            }
        }
    }

    /// Full-precision timestamp + "Who can reply" badge. Mirrors RN's
    /// `ExpandedPostDetails`: a row of small secondary text with the
    /// dot-separated date, followed by `WhoCanReply` when a threadgate
    /// is attached.
    private var timestampSubtitle: some View {
        HStack(spacing: Spacing.sm) {
            Text(formattedTimestamp(item.post.indexedAt))
                .font(Typography.bodySmall)
                .foregroundStyle(theme.colors.textSecondary)
                .accessibilityLabel("Posted \(accessibleTimestamp(item.post.indexedAt))")
            if let label = whoCanReplyLabel {
                whoCanReplyBadge(text: label)
            }
            Spacer(minLength: 0)
        }
    }

    /// Tappable engagement stats. Each is rendered only when its
    /// underlying count is non-zero, matching RN's render gate.
    private var statRow: some View {
        HStack(spacing: Spacing.lg) {
            if item.post.repostCount > 0 {
                Button {
                    onRepostedByTap?(item.post.uri)
                } label: {
                    statLabel(count: item.post.repostCount, singular: "repost", plural: "reposts")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(item.post.repostCount) reposts")
            }
            if item.post.quoteCount > 0 {
                Button {
                    onQuotesTap?(item.post.uri)
                } label: {
                    statLabel(count: item.post.quoteCount, singular: "quote", plural: "quotes")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(item.post.quoteCount) quotes")
            }
            if item.post.likeCount > 0 {
                Button {
                    onLikedByTap?(item.post.uri)
                } label: {
                    statLabel(count: item.post.likeCount, singular: "like", plural: "likes")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(item.post.likeCount) likes")
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.sm)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.colors.border).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.colors.border).frame(height: 1)
        }
    }

    private func statLabel(count: Int, singular: String, plural: String) -> some View {
        HStack(spacing: Spacing._2xs) {
            Text(CompactNumberFormatter.string(from: count))
                .font(Typography.body)
                .fontWeight(.semibold)
                .foregroundStyle(theme.colors.textPrimary)
            Text(count == 1 ? singular : plural)
                .font(Typography.body)
                .foregroundStyle(theme.colors.textSecondary)
        }
    }

    /// Action bar — same icons and order as `PostCard`'s but rendered
    /// at a slightly larger touch target. RN's `<PostControls big />`
    /// is the equivalent.
    private var actionBar: some View {
        let post = item.post
        let isLiked = post.viewer?.like != nil
        let isReposted = post.viewer?.repost != nil

        return HStack(spacing: Spacing.xl) {
            actionButton(
                icon: "bubble.left",
                color: theme.colors.textTertiary,
                helpText: "Reply",
                identifier: "post-action-reply"
            ) { actions?.onReply?(post) }

            actionButton(
                icon: "arrow.2.squarepath",
                color: isReposted ? theme.colors.success : theme.colors.textTertiary,
                helpText: "Repost",
                identifier: "post-action-repost",
                accessibilityValue: isReposted ? "reposted" : "not reposted"
            ) { actions?.onRepost?(post) }

            actionButton(
                icon: isLiked ? "heart.fill" : "heart",
                color: isLiked ? theme.colors.like : theme.colors.textTertiary,
                helpText: "Like",
                identifier: "post-action-like",
                accessibilityValue: isLiked ? "liked" : "not liked"
            ) { actions?.onLike?(post) }

            actionButton(
                icon: actions?.isBookmarked == true ? "bookmark.fill" : "bookmark",
                color: actions?.isBookmarked == true ? theme.colors.link : theme.colors.textTertiary,
                helpText: actions?.isBookmarked == true ? "Remove Bookmark" : "Bookmark",
                identifier: "post-action-bookmark"
            ) { actions?.onBookmark?(post) }

            if let url = shareURL(for: post) {
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18))
                        .foregroundStyle(theme.colors.textTertiary)
                        .help("Share")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("post-action-share")
            }

            Menu {
                Button {
                    copyStringToClipboard(post.record.text)
                } label: {
                    Label("Copy post text", systemImage: "doc.on.doc")
                }
                Button {
                    if let url = shareURL(for: post) {
                        copyStringToClipboard(url.absoluteString)
                        showCopiedToast = true
                    }
                } label: {
                    Label("Copy link to post", systemImage: "link")
                }
                .disabled(shareURL(for: post) == nil)
                Button {
                    if let url = shareURL(for: post) {
                        openURL(url)
                    }
                } label: {
                    Label("Open in browser", systemImage: "safari")
                }
                .disabled(shareURL(for: post) == nil)
                Button {
                    isTranslating = true
                } label: {
                    Label("Translate post", systemImage: "character.bubble")
                }
                .disabled(post.record.text.isEmpty)
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
                    .font(.system(size: 18))
                    .foregroundStyle(theme.colors.textTertiary)
                    .help("More actions")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.borderless)

            Spacer(minLength: 0)
        }
    }

    private func actionButton(
        icon: String,
        color: Color,
        helpText: String,
        identifier: String? = nil,
        accessibilityValue: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)
                .help(helpText)
        }
        .buttonStyle(.plain)
        // UI-test coupling surface (#0177): identifier addresses the button so
        // the thread suite can assert the focal post's action bar is present
        // and tappable; the optional value exposes like/repost toggle state.
        .accessibilityIdentifier(identifier ?? "")
        .accessibilityLabel(helpText)
        .modifier(FocalOptionalAccessibilityValue(value: accessibilityValue))
    }

    // MARK: - Helpers

    /// `true` when the focal post has any non-zero engagement metric we
    /// surface in the stat row. Mirrors RN's wrapper conditional in
    /// `ThreadItemAnchor`: render the strip only when the post has at
    /// least one of repost / quote / like.
    private var hasEngagement: Bool {
        item.post.repostCount > 0
            || item.post.likeCount > 0
            || item.post.quoteCount > 0
    }

    /// Mirrors RN's `niceDate(... 'dot separated')` →
    /// `[time, short] · [date, medium]`.
    private func formattedTimestamp(_ date: Date) -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        timeFormatter.dateStyle = .none
        let dateFormatter = DateFormatter()
        dateFormatter.timeStyle = .none
        dateFormatter.dateStyle = .medium
        return "\(timeFormatter.string(from: date)) · \(dateFormatter.string(from: date))"
    }

    /// Long-form spoken version for the accessibility label so VoiceOver
    /// reads the date naturally rather than as a punctuated string.
    private func accessibleTimestamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func shareURL(for post: PostView) -> URL? {
        let handle = post.author.handle.rawValue
        let rkey = post.uri.rawValue.components(separatedBy: "/").last ?? ""
        guard !rkey.isEmpty else { return nil }
        return URL(string: "https://bsky.app/profile/\(handle)/post/\(rkey)")
    }

    private func copyStringToClipboard(_ string: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = string
        #elseif canImport(AppKit)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
        #endif
    }

    // MARK: - "Who can reply"

    /// Translate the threadgate's `allow` rules into a one-line label,
    /// mirroring the copy in RN's `WhoCanReply` component.
    ///
    /// - `nil` → "Everyone can reply" — only shown when the post explicitly
    ///   carries a threadgate (so we don't decorate every focal post).
    ///   To keep the UI quiet, we *suppress* the badge when there is no
    ///   threadgate at all (the default), matching RN.
    /// - empty array → "Replies disabled".
    /// - non-empty array → list of allowed audiences ("Mentioned users",
    ///   "Followed users", "Followers", or "Custom list").
    private var whoCanReplyLabel: String? {
        guard let allow = threadgateAllow else { return nil }
        if allow.isEmpty {
            return "Replies disabled"
        }
        var parts: [String] = []
        for rule in allow {
            switch rule {
            case .mention: parts.append("mentioned users")
            case .following: parts.append("followed users")
            case .follower: parts.append("your followers")
            case .list: parts.append("a custom list")
            case .unknown: continue
            }
        }
        if parts.isEmpty { return nil }
        let joined = formatJoin(parts)
        return "Only \(joined) can reply"
    }

    /// Tiny English list-formatter — RN does this through `lingui`'s
    /// `Plural`/`Trans` machinery; we approximate the most common shapes
    /// without pulling in a localization dependency.
    private func formatJoin(_ parts: [String]) -> String {
        switch parts.count {
        case 0: return ""
        case 1: return parts[0]
        case 2: return "\(parts[0]) and \(parts[1])"
        default:
            let leading = parts.dropLast().joined(separator: ", ")
            return "\(leading), and \(parts.last!)"
        }
    }

    private func whoCanReplyBadge(text: String) -> some View {
        HStack(spacing: Spacing._2xs) {
            Image(systemName: "person.2")
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(Typography.bodySmall)
                .fontWeight(.semibold)
                .lineLimit(1)
        }
        .foregroundStyle(theme.colors.textSecondary)
        .padding(.vertical, Spacing._2xs)
        .padding(.horizontal, Spacing.sm)
        .background(
            Capsule().fill(theme.colors.backgroundSecondary)
        )
        .accessibilityLabel(text)
    }
}

// MARK: - FocalOptionalAccessibilityValue

/// Applies `.accessibilityValue(_:)` only when a non-nil value is supplied.
/// `accessibilityValue` has no "clear" overload, so this keeps buttons without
/// a toggle state (reply, share) free of a spurious value while letting the
/// like / repost buttons expose their state for #0177's thread-view tests.
/// A focal-post-local twin of `PostCard`'s file-private modifier.
private struct FocalOptionalAccessibilityValue: ViewModifier {
    let value: String?
    func body(content: Content) -> some View {
        if let value {
            content.accessibilityValue(value)
        } else {
            content
        }
    }
}

// MARK: - Previews

#Preview("FocalPostCard — Light") {
    let author = ProfileBasic(
        did: DID(rawValue: "did:plc:alice"),
        handle: Handle(rawValue: "alice.bsky.social"),
        displayName: "Alice Anderson",
        avatar: nil,
        verification: VerificationState(verifiedStatus: "valid", trustedVerifierStatus: "none")
    )
    let record = PostRecord(
        text: "Hello Bluesky! Check out #bluesky — the open social network. This is the focal post in a thread, so it gets the deluxe treatment.",
        createdAt: Date(timeIntervalSinceNow: -3600 * 5)
    )
    let post = PostView(
        uri: ATURI(rawValue: "at://did:plc:alice/app.bsky.feed.post/abc"),
        cid: "bafyabc",
        author: author,
        record: record,
        embed: nil,
        replyCount: 8,
        repostCount: 124,
        likeCount: 3402,
        quoteCount: 17,
        indexedAt: Date(timeIntervalSinceNow: -3600 * 5),
        viewer: nil
    )
    let item = FeedViewPost(post: post, reply: nil, reason: nil)

    ScrollView {
        FocalPostCard(
            item: item,
            actions: PostCard.Actions(),
            threadgateAllow: [.mention, .following]
        )
        Divider()
    }
    .frame(maxWidth: .infinity)
    .background(.background)
    .blueskyTheme(.light)
    .preferredColorScheme(.light)
}

#Preview("FocalPostCard — Dark") {
    let author = ProfileBasic(
        did: DID(rawValue: "did:plc:alice"),
        handle: Handle(rawValue: "alice.bsky.social"),
        displayName: "Alice Anderson",
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
        FocalPostCard(item: item, actions: PostCard.Actions())
        Divider()
    }
    .frame(maxWidth: .infinity)
    .background(.background)
    .blueskyTheme(.dark)
    .preferredColorScheme(.dark)
}
