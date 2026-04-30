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
        onEditProfile: @escaping () -> Void
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
    }

    @Environment(\.blueskyTheme) private var theme

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            bannerSection
            avatarAndActions
            nameSection
            if let desc = profile?.description, !desc.isEmpty {
                Text(desc)
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
        .frame(height: 130)
        .clipped()
    }

    private var bannerPlaceholder: some View {
        Rectangle().fill(Color.secondary.opacity(0.2))
    }

    // MARK: - Avatar + action buttons

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

    private var statsRow: some View {
        HStack(spacing: 20) {
            statView(count: profile?.followsCount ?? 0, label: "Following")
            statView(count: profile?.followersCount ?? 0, label: "Followers")
            statView(count: profile?.postsCount ?? 0, label: "Posts")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private func statView(count: Int, label: String) -> some View {
        HStack(spacing: 4) {
            Text("\(count)").fontWeight(.semibold)
            Text(label).foregroundStyle(.secondary)
        }
        .font(.subheadline)
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
