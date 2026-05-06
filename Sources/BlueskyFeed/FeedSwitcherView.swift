import SwiftUI
import BlueskyCore
import BlueskyUI

// MARK: - HomeFeedTab

/// One entry in the Home tab strip. Wraps a label and the underlying
/// `FeedSelection` that should drive the timeline content for that tab.
///
/// Built-in tabs (Following / Mentions / Discover / Popular With Friends) are
/// constructed via the `built()` helpers; user-pinned feeds come in through
/// `pinned(displayName:uri:)` so the strip can render any custom feed
/// generator the user has pinned in their preferences.
public struct HomeFeedTab: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let selection: FeedSelection

    public init(id: String, label: String, selection: FeedSelection) {
        self.id = id
        self.label = label
        self.selection = selection
    }

    // MARK: Built-in feeds

    /// AT-URI for the bsky.app curated Discover feed (`whats-hot`).
    public static let discoverURI =
        "at://did:plc:z72i7hdynmk6r22z27h6tvur/app.bsky.feed.generator/whats-hot"

    /// AT-URI for the bsky.app "Popular With Friends" feed (`with-friends`).
    /// Note this is an authed-only feed — it returns 401 for logged-out callers.
    public static let popularWithFriendsURI =
        "at://did:plc:z72i7hdynmk6r22z27h6tvur/app.bsky.feed.generator/with-friends"

    /// AT-URI for the third-party "Mentions" feed used by the React Native
    /// reference (`flicknow / mentions`). AT Proto has no first-party
    /// mentions-of-the-viewer feed lexicon, so the RN client and this client
    /// both fall back to this community-maintained generator. If it ever goes
    /// offline the strip will just surface its error message — replace the URI
    /// here to swap in a different mentions feed without touching the rest of
    /// the code.
    public static let mentionsURI =
        "at://did:plc:wzsilnxf24ehtmmc3gssy5bu/app.bsky.feed.generator/mentions"

    public static let following = HomeFeedTab(
        id: "following",
        label: "Following",
        selection: .timeline
    )

    public static let mentions = HomeFeedTab(
        id: "mentions",
        label: "Mentions",
        selection: .feed(uri: HomeFeedTab.mentionsURI)
    )

    public static let discover = HomeFeedTab(
        id: "discover",
        label: "Discover",
        selection: .feed(uri: HomeFeedTab.discoverURI)
    )

    public static let popularWithFriends = HomeFeedTab(
        id: "popular-with-friends",
        label: "Popular With Friends",
        selection: .feed(uri: HomeFeedTab.popularWithFriendsURI)
    )

    /// The fixed set of built-in tabs, in the order they appear at the start
    /// of the strip.
    public static let builtIns: [HomeFeedTab] = [
        .following,
        .mentions,
        .discover,
        .popularWithFriends,
    ]

    /// Build a tab for a user-pinned feed entry.
    public static func pinned(displayName: String, uri: String) -> HomeFeedTab {
        HomeFeedTab(
            id: "pinned:\(uri)",
            label: displayName,
            selection: .feed(uri: uri)
        )
    }
}

// MARK: - FeedSwitcherView

/// Horizontally-scrollable tab strip for the Home screen.
///
/// Shows the four built-in tabs (Following · Mentions · Discover · Popular
/// With Friends) followed by the user's pinned feeds in their saved-pin
/// order. The active tab gets a 2pt brand-color underline. The strip
/// auto-scrolls to keep the active tab visible whenever the selection
/// changes — used both when the user taps a tab and when the underlying
/// feed pager swipes between adjacent tabs (#0074).
///
/// Delegates the visual treatment to `UnderlineTabStrip` (BlueskyUI) so
/// Home (#0074) and Profile (#0086) share the same underline component.
public struct FeedSwitcherView: View {

    @Binding private var selectedID: String
    private let tabs: [HomeFeedTab]
    private let onTap: ((HomeFeedTab) -> Void)?

    public init(
        tabs: [HomeFeedTab],
        selectedID: Binding<String>,
        onTap: ((HomeFeedTab) -> Void)? = nil
    ) {
        self.tabs = tabs
        self._selectedID = selectedID
        self.onTap = onTap
    }

    public var body: some View {
        UnderlineTabStrip(
            tabs: tabs.map { UnderlineTab(id: $0.id, label: $0.label) },
            selectedID: $selectedID,
            onTap: { underlineTab in
                if let tab = tabs.first(where: { $0.id == underlineTab.id }) {
                    onTap?(tab)
                }
            }
        )
    }
}

// MARK: - Previews

#Preview("FeedSwitcherView — Light") {
    @Previewable @State var selectedID: String = HomeFeedTab.following.id
    let tabs = HomeFeedTab.builtIns + [
        HomeFeedTab.pinned(displayName: "Art", uri: "at://example/art"),
        HomeFeedTab.pinned(displayName: "Bookworms", uri: "at://example/books"),
    ]
    FeedSwitcherView(tabs: tabs, selectedID: $selectedID)
        .blueskyTheme(.light)
        .preferredColorScheme(.light)
}

#Preview("FeedSwitcherView — Dark") {
    @Previewable @State var selectedID: String = HomeFeedTab.following.id
    let tabs = HomeFeedTab.builtIns
    FeedSwitcherView(tabs: tabs, selectedID: $selectedID)
        .blueskyTheme(.dark)
        .preferredColorScheme(.dark)
}
