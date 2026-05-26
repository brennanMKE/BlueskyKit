import SwiftUI
import BlueskyCore
import Translation
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
    @Environment(\.openURL) private var openURL

    /// Toggles the system Translation popover (`.translationPresentation`).
    /// Set by the inline "Translate" link and the ellipsis-menu "Translate
    /// post" item — RN parity (#0143). Mirrors the per-message translate
    /// pattern from #0106.
    @State private var isTranslating: Bool = false

    /// Drives the "Copied to clipboard" toast triggered by the ellipsis menu's
    /// "Copy link to post" action — RN parity (#0144). Mirrors the
    /// `Toast.show(...)` call in `ShareMenuItems.tsx`.
    @State private var showCopiedToast: Bool = false

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
                        if shouldShowInlineTranslate {
                            translateLink
                        }
                        if let embed = item.post.embed {
                            embedView(for: embed)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        actions?.onTap?(item.post)
                    }
                    // UI-test / VoiceOver coupling surface (#0184): expose the
                    // open-thread tap region as a discrete, button-trait element
                    // carrying an explicit accessibility action that invokes the
                    // same `onTap`. A synthetic XCUITest `.tap()` (and a
                    // VoiceOver activate) fires `.accessibilityAction`, whereas a
                    // bare `.onTapGesture` is not reliably triggered by a
                    // synthetic tap on a combined a11y element. Tapping the
                    // whole-cell `post-cell` container is also unreliable — its
                    // centre can land on the avatar column, an image embed
                    // (which has its own button), or the action bar, none of
                    // which open the thread. Only surfaced when an `onTap` is
                    // wired so read-only cards (e.g. notification rows) don't
                    // advertise a non-functional target.
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction {
                        actions?.onTap?(item.post)
                    }
                    .accessibilityIdentifier(actions?.onTap != nil ? "post-open-thread" : "")
                    actionBar
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
        .background(theme.colors.background)
        // UI-test coupling surface (#0176): identify the post cell and expose
        // its key text as the accessibility label so the suite can assert the
        // cell exists and renders content. `children: .contain` keeps the
        // nested action buttons individually addressable.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("post-cell")
        // Drives the system Translate sheet (#0143). Mirrors the RN
        // `TranslatedPost` flow: tapping the inline "Translate" link or the
        // ellipsis-menu "Translate post" item flips this flag, which presents
        // Apple's TranslationKit UI on iOS 17.4+ / macOS 14.4+.
        .translationPresentation(isPresented: $isTranslating, text: item.post.record.text)
        // Brief confirmation after "Copy link to post" (#0144), mirroring
        // RN's `Toast.show("Copied to clipboard")` in `ShareMenuItems.tsx`.
        .toast(isPresented: $showCopiedToast, message: "Copied to clipboard")
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
        // UI-test coupling surface (#0178): the other-profile suite taps this
        // to navigate to a post author's profile from the home feed (#0046).
        .accessibilityIdentifier("post-author-avatar")
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

    /// Inline "Translate" affordance shown directly below the post body when
    /// the post's declared language differs from the viewer's current
    /// language. RN parity (#0143): mirrors `TranslatedPost`'s
    /// `TranslationLink`. Tapping it flips `isTranslating`, which presents
    /// the system translation sheet via `.translationPresentation(...)`.
    private var translateLink: some View {
        Button {
            isTranslating = true
        } label: {
            Text("Translate")
                .font(Typography.bodySmall)
                .foregroundStyle(theme.colors.link)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Translate post")
    }

    /// `true` when the post body has enough text to warrant translation and
    /// its declared language differs from the viewer's current language.
    /// Pragmatic check (per #0143 spec): compares `post.record.langs[0]`
    /// against `Locale.current.language.languageCode`. A real implementation
    /// would use the user's content-language preferences from
    /// `LanguageSettingsViewModel`, but the BCP-47 primary tag check is a
    /// reasonable first pass that matches RN behavior on monolingual users.
    private var shouldShowInlineTranslate: Bool {
        let text = item.post.record.text
        guard text.count > 20 else { return false }
        guard let postLang = item.post.record.langs?.first, !postLang.isEmpty else {
            return false
        }
        let viewerLang = Locale.current.language.languageCode?.identifier
            ?? Locale.current.identifier.split(separator: "-").first.map(String.init)
            ?? "en"
        // BCP-47 tags can include region/script subtags (e.g. "en-US",
        // "zh-Hant"); compare only the primary language subtag.
        let postPrimary = postLang.split(separator: "-").first.map(String.init)?.lowercased() ?? ""
        return postPrimary != viewerLang.lowercased()
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
                helpText: "Reply",
                identifier: "post-action-reply"
            ) { actions?.onReply?(post) }

            actionButton(
                icon: "arrow.2.squarepath",
                count: post.repostCount,
                color: isReposted ? theme.colors.success : theme.colors.textTertiary,
                helpText: "Repost",
                identifier: "post-action-repost",
                accessibilityValue: isReposted ? "reposted" : "not reposted"
            ) { actions?.onRepost?(post) }

            actionButton(
                icon: isLiked ? "heart.fill" : "heart",
                count: post.likeCount,
                color: isLiked ? theme.colors.like : theme.colors.textTertiary,
                helpText: "Like",
                identifier: "post-action-like",
                // UI-test coupling surface (#0176): the like test taps this
                // button and asserts the value flips, so the local-state
                // regressions (#0041 / #0053) surface on the next CI run.
                accessibilityValue: isLiked ? "liked" : "not liked"
            ) { actions?.onLike?(post) }

            actionButton(
                icon: actions?.isBookmarked == true ? "bookmark.fill" : "bookmark",
                count: nil,
                color: actions?.isBookmarked == true ? theme.colors.link : theme.colors.textTertiary,
                helpText: actions?.isBookmarked == true ? "Remove Bookmark" : "Bookmark",
                identifier: "post-action-bookmark"
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
                .accessibilityIdentifier("post-action-share")
            }

            Menu {
                Button {
                    let text = post.record.text
                    copyStringToClipboard(text)
                } label: {
                    Label("Copy post text", systemImage: "doc.on.doc")
                }

                // RN parity (#0144): "Copy link to post" puts the bsky.app URL
                // on the clipboard and shows a brief "Copied to clipboard"
                // toast — mirrors `onCopyLink` in
                // `ShareMenuItems.tsx`. Disabled if we can't compute a URL
                // (no rkey).
                Button {
                    if let url = shareURL(for: post) {
                        copyStringToClipboard(url.absoluteString)
                        showCopiedToast = true
                    }
                } label: {
                    Label("Copy link to post", systemImage: "link")
                }
                .disabled(shareURL(for: post) == nil)

                // RN's web client opens the same `bsky.app/profile/.../post/...`
                // URL in a new tab; on Apple platforms we route through
                // `openURL` so it lands in the user's default browser.
                Button {
                    if let url = shareURL(for: post) {
                        openURL(url)
                    }
                } label: {
                    Label("Open in browser", systemImage: "safari")
                }
                .disabled(shareURL(for: post) == nil)

                // RN parity (#0143): "Translate post" is offered in the
                // ellipsis menu regardless of the post's source language.
                // Disabled when the post body is empty (image-only post).
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

    /// Cross-platform clipboard write used by the ellipsis menu's
    /// "Copy post text" and "Copy link to post" actions (#0144).
    private func copyStringToClipboard(_ string: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = string
        #elseif canImport(AppKit)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
        #endif
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
        identifier: String? = nil,
        accessibilityValue: String? = nil,
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
        // UI-test coupling surface (#0176). Identifier addresses the button;
        // the accessibility value (when supplied) lets a test assert toggle
        // state flips after a tap. The help text doubles as the a11y label.
        .accessibilityIdentifier(identifier ?? "")
        .accessibilityLabel(helpText)
        .modifier(OptionalAccessibilityValue(value: accessibilityValue))
    }

}

// MARK: - OptionalAccessibilityValue

/// Applies `.accessibilityValue(_:)` only when a non-nil value is supplied.
/// `accessibilityValue` has no "clear" overload, so this keeps buttons without
/// a toggle state (reply, share) free of a spurious value while letting the
/// like / repost buttons expose their state for #0176's interaction tests.
private struct OptionalAccessibilityValue: ViewModifier {
    let value: String?
    func body(content: Content) -> some View {
        if let value {
            content.accessibilityValue(value)
        } else {
            content
        }
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
