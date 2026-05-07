import SwiftUI
import BlueskyCore

/// Maximum number of lines a post body is allowed to render before the
/// "Show More" affordance is shown.
///
/// Mirrors `MAX_POST_LINES` in
/// `Bluesky-ReactNative/src/lib/constants.ts` (= 25).
public let MAX_POST_LINES: Int = 25

/// Counts the number of newline characters in a string — RN parity with
/// `countLines` in `Bluesky-ReactNative/src/lib/strings/helpers.ts`.
///
/// Matches RN exactly: counts `"\n"` occurrences (not visual line wraps).
@inlinable
public func countPostLines(_ text: String?) -> Int {
    guard let text else { return 0 }
    var count = 0
    for ch in text where ch == "\n" { count += 1 }
    return count
}

/// Reusable post-body renderer.
///
/// Wraps `RichTextView` with the same font, foreground color, and link
/// behavior used by `PostCard.postBody` so that surfaces outside the feed
/// (notification rows, search previews, etc.) can render identical text.
///
/// ### Long-post expansion (#0142)
///
/// When `lineLimit` is `nil` and the body has at least `MAX_POST_LINES`
/// newlines, the text is clamped to `MAX_POST_LINES` and a **"Show More"**
/// button is rendered below it. Tapping the button expands the body to its
/// full length and the button disappears — RN parity (`ShowMoreTextButton`
/// only shows "Show More"; once expanded, there is no "Show Less" return).
///
/// Pass `isFocal: true` to bypass the clamp entirely (used by the focal
/// post in a thread, per #0146). Passing an explicit non-`nil` `lineLimit`
/// (e.g. `4` from notification rows) keeps the legacy hard-cap behavior
/// without an expansion control.
public struct PostBodyView: View {

    public let text: String
    public let facets: [RichTextFacet]?
    public let lineLimit: Int?
    public let isFocal: Bool
    public var onHashtagTap: ((String) -> Void)?
    public var onLinkTap: ((URL) -> Void)?
    public var onMentionTap: ((DID) -> Void)?

    @Environment(\.blueskyTheme) private var theme

    /// Local expansion state — once the user taps "Show More" we render the
    /// full body. Resets when the view is recycled to a different post.
    @State private var isExpanded: Bool = false

    public init(
        text: String,
        facets: [RichTextFacet]? = nil,
        lineLimit: Int? = nil,
        isFocal: Bool = false,
        onHashtagTap: ((String) -> Void)? = nil,
        onLinkTap: ((URL) -> Void)? = nil,
        onMentionTap: ((DID) -> Void)? = nil
    ) {
        self.text = text
        self.facets = facets
        self.lineLimit = lineLimit
        self.isFocal = isFocal
        self.onHashtagTap = onHashtagTap
        self.onLinkTap = onLinkTap
        self.onMentionTap = onMentionTap
    }

    /// `true` when the body is long enough to warrant the "Show More" button
    /// AND the caller has not opted out (`isFocal` or an explicit
    /// `lineLimit`). RN clamps when `countLines(text) >= MAX_POST_LINES`.
    private var shouldOfferExpansion: Bool {
        guard !isFocal, lineLimit == nil else { return false }
        return countPostLines(text) >= MAX_POST_LINES
    }

    private var effectiveLineLimit: Int? {
        if let lineLimit { return lineLimit }
        if shouldOfferExpansion && !isExpanded { return MAX_POST_LINES }
        return nil
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
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
            .lineLimit(effectiveLineLimit)

            if shouldOfferExpansion && !isExpanded {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded = true
                    }
                } label: {
                    Text("Show More")
                        .font(Typography.body)
                        .foregroundStyle(theme.colors.link)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Expand post text")
            }
        }
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
        Divider()
        PostBodyView(
            text: (1...30).map { "Line \($0) of a very long post body" }.joined(separator: "\n")
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
        Divider()
        PostBodyView(
            text: (1...30).map { "Line \($0) of a very long post body" }.joined(separator: "\n")
        )
    }
    .padding()
    .frame(maxWidth: .infinity)
    .blueskyTheme(.dark)
    .preferredColorScheme(.dark)
}
