import SwiftUI
import BlueskyCore

/// Reusable post-body renderer.
///
/// Wraps `RichTextView` with the same font, foreground color, and link
/// behavior used by `PostCard.postBody` so that surfaces outside the feed
/// (notification rows, search previews, etc.) can render identical text.
///
/// `lineLimit` defaults to `nil` (uncapped, matching `PostCard`); callers
/// like the notifications row pass `4` to clamp the preview.
public struct PostBodyView: View {

    public let text: String
    public let facets: [RichTextFacet]?
    public let lineLimit: Int?
    public var onHashtagTap: ((String) -> Void)?
    public var onLinkTap: ((URL) -> Void)?
    public var onMentionTap: ((DID) -> Void)?

    @Environment(\.blueskyTheme) private var theme

    public init(
        text: String,
        facets: [RichTextFacet]? = nil,
        lineLimit: Int? = nil,
        onHashtagTap: ((String) -> Void)? = nil,
        onLinkTap: ((URL) -> Void)? = nil,
        onMentionTap: ((DID) -> Void)? = nil
    ) {
        self.text = text
        self.facets = facets
        self.lineLimit = lineLimit
        self.onHashtagTap = onHashtagTap
        self.onLinkTap = onLinkTap
        self.onMentionTap = onMentionTap
    }

    public var body: some View {
        RichTextView(
            text: text,
            facets: facets,
            foregroundColor: theme.colors.textPrimary,
            linkColor: theme.colors.link,
            onLinkTap: { url in
                if url.scheme == "bluesky", url.host == "hashtag",
                   let tag = url.pathComponents.last, !tag.isEmpty {
                    onHashtagTap?(tag)
                } else if url.scheme == "bluesky", url.host == "profile",
                          let did = url.pathComponents.last, !did.isEmpty {
                    onMentionTap?(DID(rawValue: did))
                } else {
                    onLinkTap?(url)
                }
            }
        )
        .lineLimit(lineLimit)
    }
}

#Preview("PostBodyView — Light") {
    VStack(alignment: .leading, spacing: 16) {
        PostBodyView(
            text: "Hello @alice.bsky.social! Check out https://bsky.app and #bluesky — the open social network."
        )
        Divider()
        PostBodyView(
            text: "This is a long post that will be clamped to four lines when used inside a notification row. " +
                  "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Ut enim ad minim veniam, " +
                  "quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. " +
                  "Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore.",
            lineLimit: 4
        )
    }
    .padding()
    .frame(maxWidth: .infinity)
    .blueskyTheme(.light)
    .preferredColorScheme(.light)
}

#Preview("PostBodyView — Dark") {
    VStack(alignment: .leading, spacing: 16) {
        PostBodyView(
            text: "Hello @alice.bsky.social! Check out https://bsky.app and #bluesky — the open social network."
        )
        Divider()
        PostBodyView(
            text: "This is a long post that will be clamped to four lines when used inside a notification row. " +
                  "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Ut enim ad minim veniam, " +
                  "quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. " +
                  "Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore.",
            lineLimit: 4
        )
    }
    .padding()
    .frame(maxWidth: .infinity)
    .blueskyTheme(.dark)
    .preferredColorScheme(.dark)
}
