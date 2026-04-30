import SwiftUI
import BlueskyCore

/// A card showing a custom feed ("algorithm"), including its display name, description,
/// creator handle, and like count.  Tapping the card calls `onTap`.
public struct FeedCard: View {

    let feed: GeneratorView
    var onTap: ((GeneratorView) -> Void)?

    @Environment(\.blueskyTheme) private var theme

    public init(feed: GeneratorView, onTap: ((GeneratorView) -> Void)? = nil) {
        self.feed = feed
        self.onTap = onTap
    }

    public var body: some View {
        Button { onTap?(feed) } label: {
            HStack(spacing: Spacing.sm) {
                AvatarView(url: feed.avatar, handle: feed.displayName, size: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: Spacing._2xs) {
                    Text(feed.displayName)
                        .font(Typography.headline)
                        .foregroundStyle(theme.colors.textPrimary)

                    Text("by @\(feed.creator.handle.rawValue)")
                        .font(Typography.footnote)
                        .foregroundStyle(theme.colors.textTertiary)

                    if let desc = feed.description, !desc.isEmpty {
                        Text(desc)
                            .font(Typography.bodySmall)
                            .foregroundStyle(theme.colors.textSecondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)

                if let likeCount = feed.likeCount, likeCount > 0 {
                    Label(abbreviate(likeCount), systemImage: "heart")
                        .font(Typography.footnote)
                        .foregroundStyle(theme.colors.textTertiary)
                }
            }
            .padding(.vertical, Spacing.sm)
            .padding(.horizontal, Spacing.md)
            .background(theme.colors.background)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func abbreviate(_ n: Int) -> String {
        if n < 1000 { return "\(n)" }
        return "\(n / 1000)K"
    }
}

#Preview("FeedCard — Light") {
    let creator = ProfileView(
        did: DID(rawValue: "did:plc:xyz"),
        handle: Handle(rawValue: "bsky.app"),
        displayName: "Bluesky",
        description: nil,
        avatar: nil,
        indexedAt: nil,
        viewer: nil
    )
    let feed = GeneratorView(
        uri: ATURI(rawValue: "at://did:plc:xyz/app.bsky.feed.generator/whats-hot"),
        cid: "bafyxyz",
        did: DID(rawValue: "did:web:discover.bsky.app"),
        creator: creator,
        displayName: "Discover",
        description: "Top posts from across the network, ranked by engagement.",
        likeCount: 24000
    )
    FeedCard(feed: feed)
        .frame(maxWidth: .infinity)
        .background(.background)
        .blueskyTheme(.light)
        .preferredColorScheme(.light)
}

#Preview("FeedCard — Dark") {
    let creator = ProfileView(
        did: DID(rawValue: "did:plc:xyz"),
        handle: Handle(rawValue: "bsky.app"),
        displayName: "Bluesky",
        description: nil,
        avatar: nil,
        indexedAt: nil,
        viewer: nil
    )
    let feed = GeneratorView(
        uri: ATURI(rawValue: "at://did:plc:xyz/app.bsky.feed.generator/whats-hot"),
        cid: "bafyxyz",
        did: DID(rawValue: "did:web:discover.bsky.app"),
        creator: creator,
        displayName: "Discover",
        description: "Top posts from across the network, ranked by engagement.",
        likeCount: 24000
    )
    FeedCard(feed: feed)
        .frame(maxWidth: .infinity)
        .background(.background)
        .blueskyTheme(.dark)
        .preferredColorScheme(.dark)
}
