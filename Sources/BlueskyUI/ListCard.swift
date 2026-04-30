import SwiftUI
import BlueskyCore

/// A card showing a curated list or moderation list.
public struct ListCard: View {

    let list: ListView
    var onTap: ((ListView) -> Void)?

    @Environment(\.blueskyTheme) private var theme

    public init(list: ListView, onTap: ((ListView) -> Void)? = nil) {
        self.list = list
        self.onTap = onTap
    }

    public var body: some View {
        Button { onTap?(list) } label: {
            HStack(spacing: Spacing.sm) {
                AvatarView(url: list.avatar, handle: list.name, size: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: Spacing._2xs) {
                    HStack(spacing: Spacing.xs) {
                        Text(list.name)
                            .font(Typography.headline)
                            .foregroundStyle(theme.colors.textPrimary)

                        if list.purpose == "app.bsky.graph.defs#modlist" {
                            Text("MOD")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(theme.colors.error.opacity(0.15))
                                .foregroundStyle(theme.colors.error)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }

                    Text("by @\(list.creator.handle.rawValue)")
                        .font(Typography.footnote)
                        .foregroundStyle(theme.colors.textTertiary)

                    if let desc = list.description, !desc.isEmpty {
                        Text(desc)
                            .font(Typography.bodySmall)
                            .foregroundStyle(theme.colors.textSecondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.colors.textTertiary)
            }
            .padding(.vertical, Spacing.sm)
            .padding(.horizontal, Spacing.md)
            .background(theme.colors.background)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview("ListCard — Light") {
    let creator = ProfileView(
        did: DID(rawValue: "did:plc:xyz"),
        handle: Handle(rawValue: "bsky.app"),
        displayName: "Bluesky",
        description: nil,
        avatar: nil,
        indexedAt: nil,
        viewer: nil
    )
    let list = ListView(
        uri: ATURI(rawValue: "at://did:plc:xyz/app.bsky.graph.list/abc"),
        cid: "bafyabc",
        creator: creator,
        name: "Swift Developers",
        purpose: "app.bsky.graph.defs#curatelist",
        description: "People building great things with Swift.",
        avatar: nil,
        indexedAt: .now
    )
    ListCard(list: list)
        .frame(maxWidth: .infinity)
        .background(.background)
        .blueskyTheme(.light)
        .preferredColorScheme(.light)
}

#Preview("ListCard — Dark") {
    let creator = ProfileView(
        did: DID(rawValue: "did:plc:xyz"),
        handle: Handle(rawValue: "bsky.app"),
        displayName: "Bluesky",
        description: nil,
        avatar: nil,
        indexedAt: nil,
        viewer: nil
    )
    let list = ListView(
        uri: ATURI(rawValue: "at://did:plc:xyz/app.bsky.graph.list/abc"),
        cid: "bafyabc",
        creator: creator,
        name: "Swift Developers",
        purpose: "app.bsky.graph.defs#curatelist",
        description: "People building great things with Swift.",
        avatar: nil,
        indexedAt: .now
    )
    ListCard(list: list)
        .frame(maxWidth: .infinity)
        .background(.background)
        .blueskyTheme(.dark)
        .preferredColorScheme(.dark)
}
