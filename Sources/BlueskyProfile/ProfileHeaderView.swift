import SwiftUI
import BlueskyCore
import BlueskyUI

public struct ProfileHeaderView: View {

    let profile: ProfileDetailed?
    let isOwnProfile: Bool
    let knownFollowers: [ProfileView]
    let onFollow: () -> Void
    let onUnfollow: () -> Void
    let onBlock: () -> Void
    let onUnblock: () -> Void
    let onMute: () -> Void
    let onUnmute: () -> Void
    let onEditProfile: () -> Void
    /// Optional own-profile menu actions surfaced via the in-screen ellipsis
    /// (iOS only — see #0083). When `nil` the menu falls back to no-op or omits
    /// the entry. macOS routes these through the toolbar instead.
    let onSettings: (() -> Void)?
    let onSaved: (() -> Void)?
    let onMyLists: (() -> Void)?
    let onModeration: (() -> Void)?

    public init(
        profile: ProfileDetailed?,
        isOwnProfile: Bool,
        knownFollowers: [ProfileView] = [],
        onFollow: @escaping () -> Void,
        onUnfollow: @escaping () -> Void,
        onBlock: @escaping () -> Void,
        onUnblock: @escaping () -> Void,
        onMute: @escaping () -> Void,
        onUnmute: @escaping () -> Void,
        onEditProfile: @escaping () -> Void,
        onSettings: (() -> Void)? = nil,
        onSaved: (() -> Void)? = nil,
        onMyLists: (() -> Void)? = nil,
        onModeration: (() -> Void)? = nil
    ) {
        self.profile = profile
        self.isOwnProfile = isOwnProfile
        self.knownFollowers = knownFollowers
        self.onFollow = onFollow
        self.onUnfollow = onUnfollow
        self.onBlock = onBlock
        self.onUnblock = onUnblock
        self.onMute = onMute
        self.onUnmute = onUnmute
        self.onEditProfile = onEditProfile
        self.onSettings = onSettings
        self.onSaved = onSaved
        self.onMyLists = onMyLists
        self.onModeration = onModeration
    }

    @Environment(\.blueskyTheme) private var theme

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            bannerSection
            #if os(iOS)
            iosAvatarAndActions
            #else
            avatarAndActions
            #endif
            nameSection
            if let desc = profile?.description, !desc.isEmpty {
                // #0084: detect URLs in the description and render them with
                // the protocol prefix stripped (`brennan.sstools.co` instead
                // of `https://brennan.sstools.co`) while keeping the link
                // tappable to the full URL.
                Text(profileDescriptionAttributed(desc))
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
            statsRow
            if !knownFollowers.isEmpty {
                knownFollowersChip
            }
            Divider().padding(.top, 12)
        }
    }

    // MARK: - Banner

    private var bannerSection: some View {
        Group {
            if let bannerURL = profile?.banner {
                AsyncImage(url: bannerURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        bannerPlaceholder
                    }
                }
            } else {
                bannerPlaceholder
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: bannerHeight)
        .clipped()
        #if os(iOS)
        // Run the banner flush under the status bar (#0083). The rest of the
        // header keeps its safe-area inset; only the banner ignores it.
        .ignoresSafeArea(edges: .top)
        #endif
    }

    private var bannerHeight: CGFloat {
        #if os(iOS)
        // Slightly taller on iOS to absorb the status-bar inset that we now
        // bleed into. macOS keeps the historical 130pt height.
        return 150
        #else
        return 130
        #endif
    }

    private var bannerPlaceholder: some View {
        Rectangle().fill(Color.secondary.opacity(0.2))
    }

    // MARK: - Avatar + action buttons (macOS layout)

    private var avatarAndActions: some View {
        HStack(alignment: .bottom) {
            AvatarView(url: profile?.avatar, handle: profile?.handle.rawValue ?? "", size: 72)
                .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: 3))
                .offset(y: -24)
                .padding(.leading, 16)
            Spacer()
            actionButtons
                .padding(.trailing, 16)
                .padding(.top, 8)
        }
        .padding(.bottom, -16)
    }

    @ViewBuilder
    private var actionButtons: some View {
        if isOwnProfile {
            Button("Edit Profile", action: onEditProfile)
                .buttonStyle(.bordered)
        } else if let viewer = profile?.viewer {
            HStack(spacing: 8) {
                followButton(viewer: viewer)
                moreMenu(viewer: viewer)
            }
        }
    }

    @ViewBuilder
    private func followButton(viewer: ProfileViewerState) -> some View {
        if viewer.following != nil {
            Button("Following", action: onUnfollow)
                .buttonStyle(.bordered)
        } else {
            Button("Follow", action: onFollow)
                .buttonStyle(.borderedProminent)
        }
    }

    private func moreMenu(viewer: ProfileViewerState) -> some View {
        Menu {
            if viewer.blocking != nil {
                Button("Unblock", role: .destructive, action: onUnblock)
            } else {
                Button("Block", role: .destructive, action: onBlock)
            }
            if viewer.muted == true {
                Button("Unmute", action: onUnmute)
            } else {
                Button("Mute", action: onMute)
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 36, height: 36)
                .background(Color.secondary.opacity(0.15), in: Circle())
        }
    }

    // MARK: - Avatar + action buttons (iOS layout, #0083)

    #if os(iOS)
    /// iOS layout per #0083: banner is edge-to-edge above; the avatar overlaps
    /// the banner bottom-left without a ring; the Edit Profile pill and
    /// blue-dotted ellipsis sit in their own right-aligned row at the same
    /// vertical band as the avatar overlap.
    private var iosAvatarAndActions: some View {
        HStack(alignment: .top) {
            AvatarView(url: profile?.avatar, handle: profile?.handle.rawValue ?? "", size: 84)
                .offset(y: -42) // half-overlap: avatar size 84 / 2
                .padding(.leading, 16)
            Spacer()
            iosActionRow
                .padding(.trailing, 16)
                .padding(.top, 12)
        }
        // Pull the next section up so we don't double-count the avatar's
        // negative offset as empty space.
        .padding(.bottom, -42)
    }

    @ViewBuilder
    private var iosActionRow: some View {
        if isOwnProfile {
            HStack(spacing: 8) {
                Button("Edit Profile", action: onEditProfile)
                    .buttonStyle(.bordered)
                    .clipShape(Capsule())
                ownProfileEllipsisMenu
            }
        } else if let viewer = profile?.viewer {
            HStack(spacing: 8) {
                followButton(viewer: viewer)
                moreMenu(viewer: viewer)
                    .overlay(alignment: .topTrailing) { blueDotIndicator }
            }
        }
    }

    private var ownProfileEllipsisMenu: some View {
        Menu {
            if let onSettings { Button("Settings", systemImage: "gear", action: onSettings) }
            if let onSaved { Button("Saved", systemImage: "bookmark", action: onSaved) }
            if let onMyLists { Button("My Lists", systemImage: "list.bullet", action: onMyLists) }
            if let onModeration { Button("Moderation", systemImage: "shield", action: onModeration) }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 36, height: 36)
                .background(Color.secondary.opacity(0.15), in: Circle())
                .overlay(alignment: .topTrailing) { blueDotIndicator }
        }
    }

    /// 6pt blue indicator dot for "unviewed menu items" — currently always
    /// shown as a placeholder (see #0083 gotcha). Wire to a real signal
    /// before declaring the indicator behavior final.
    private var blueDotIndicator: some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: 6, height: 6)
            .offset(x: -2, y: 2)
    }
    #endif

    // MARK: - Name + handle

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(profile?.displayName ?? profile?.handle.rawValue ?? "")
                    .font(.title3).fontWeight(.bold)
                if profile?.labels.contains(where: { $0.val == "verified" }) == true {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.blue)
                        .font(.system(size: 14))
                }
            }
            Text("@\(profile?.handle.rawValue ?? "")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 28)
    }

    // MARK: - Known followers chip

    private var knownFollowersChip: some View {
        Text(knownFollowersText)
            .font(Typography.bodySmall)
            .foregroundStyle(theme.colors.textSecondary)
            .padding(.horizontal, 16)
            .padding(.top, Spacing._2xs)
    }

    private var knownFollowersText: String {
        let handles = knownFollowers.map { "@\($0.handle.rawValue)" }
        switch handles.count {
        case 1:
            return "Followed by \(handles[0])"
        case 2:
            return "Followed by \(handles[0]) and \(handles[1])"
        default:
            let listed = handles.dropLast().joined(separator: ", ")
            return "Followed by \(listed), and others you follow"
        }
    }

    // MARK: - Stats

    /// Stats row per #0084:
    ///  - **Followers first**, then following, then posts (RN order).
    ///  - **Lowercase labels** ("followers", "following", "posts").
    ///  - Counts pass through `CompactNumberFormatter` so 1,424 reads as "1.4K".
    private var statsRow: some View {
        HStack(spacing: 20) {
            statView(count: profile?.followersCount ?? 0, label: "followers")
            statView(count: profile?.followsCount ?? 0, label: "following")
            statView(count: profile?.postsCount ?? 0, label: "posts")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private func statView(count: Int, label: String) -> some View {
        HStack(spacing: 4) {
            Text(CompactNumberFormatter.string(from: count)).fontWeight(.semibold)
            Text(label).foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }

    // MARK: - Description rendering

    /// Build an `AttributedString` for the profile description that detects
    /// http/https URLs and replaces their *display text* with the
    /// protocol-stripped form via `URL.displayString` while keeping the link
    /// pointed at the original URL for tap handling. Non-URL text is left
    /// untouched. (See #0084 item 4.)
    private func profileDescriptionAttributed(_ raw: String) -> AttributedString {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return AttributedString(raw)
        }

        let nsRaw = raw as NSString
        let fullRange = NSRange(location: 0, length: nsRaw.length)
        let matches = detector.matches(in: raw, options: [], range: fullRange)

        var result = AttributedString()
        var cursor = 0

        for match in matches {
            // Append untouched text before the match.
            if match.range.location > cursor {
                let prefixRange = NSRange(location: cursor, length: match.range.location - cursor)
                result += AttributedString(nsRaw.substring(with: prefixRange))
            }

            let originalText = nsRaw.substring(with: match.range)
            let url = match.url ?? URL(string: originalText)
            let display = url?.displayString ?? originalText.urlDisplayString

            var run = AttributedString(display)
            run.foregroundColor = theme.colors.link
            run.link = url
            result += run

            cursor = match.range.location + match.range.length
        }

        // Trailing text after the last URL.
        if cursor < nsRaw.length {
            let tailRange = NSRange(location: cursor, length: nsRaw.length - cursor)
            result += AttributedString(nsRaw.substring(with: tailRange))
        }

        return result
    }
}

// MARK: - Previews

private let previewProfile = ProfileDetailed(
    did: DID(rawValue: "did:plc:alice"),
    handle: Handle(rawValue: "alice.bsky.social"),
    displayName: "Alice",
    description: "Building the open social web. Bluesky enthusiast.",
    avatar: nil,
    banner: nil,
    followersCount: 1240,
    followsCount: 320,
    postsCount: 487,
    labels: [],
    createdAt: nil,
    indexedAt: nil,
    viewer: ProfileViewerState(
        muted: false,
        mutedByList: nil,
        blockedBy: false,
        blocking: nil,
        following: nil,
        followedBy: nil
    )
)

#Preview("ProfileHeaderView — Light") {
    ScrollView {
        ProfileHeaderView(
            profile: previewProfile,
            isOwnProfile: false,
            knownFollowers: [],
            onFollow: {},
            onUnfollow: {},
            onBlock: {},
            onUnblock: {},
            onMute: {},
            onUnmute: {},
            onEditProfile: {}
        )
        .blueskyTheme(.light)
    }
    .preferredColorScheme(.light)
}

#Preview("ProfileHeaderView — Dark") {
    ScrollView {
        ProfileHeaderView(
            profile: previewProfile,
            isOwnProfile: false,
            knownFollowers: [],
            onFollow: {},
            onUnfollow: {},
            onBlock: {},
            onUnblock: {},
            onMute: {},
            onUnmute: {},
            onEditProfile: {}
        )
        .blueskyTheme(.dark)
    }
    .preferredColorScheme(.dark)
}
