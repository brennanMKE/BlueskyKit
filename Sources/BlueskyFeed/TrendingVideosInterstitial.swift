import SwiftUI
import BlueskyCore
import BlueskyKit
import BlueskyUI

/// "Trending Videos" interstitial section (#0205).
///
/// RN parity: `Bluesky-ReactNative/src/components/interstitials/TrendingVideos.tsx`
/// — a horizontally scrolling rail of compact 9:16 video cards sourced from the
/// `thevids` video algorithm feed, inserted into the Discover timeline after
/// the 15th slice (`PostFeed.tsx`, `sliceIndex === 15`). Tapping a card opens
/// the immersive `VideoFeed` screen seeded at the tapped post; the trailing
/// "View more" card opens the video feed generator's timeline.
///
/// The section hides itself entirely when the video feed fails to load or
/// contains no video posts — RN returns `null` on error.
public struct TrendingVideosInterstitial: View {

    /// RN: `CARD_WIDTH = 108` in `interstitials/TrendingVideos.tsx`.
    private static let cardWidth: CGFloat = 108
    /// Card height from the RN 9:16 `aspectRatio`.
    private static let cardHeight: CGFloat = 108 * 16 / 9
    /// RN: cards clamp to the first 8 video posts (`slice(0, 8)`).
    private static let maxCards = 8

    private let onVideoTap: (PostView) -> Void
    private let onViewMoreTap: (() -> Void)?

    /// Feed view model for the video algorithm feed. Created in `init` (same
    /// `@State` pattern as `VideoFeedView`) and loaded lazily on first
    /// appearance — the interstitial sits ~15 rows deep in a `LazyVStack`,
    /// so the fetch only fires when the user actually scrolls near it.
    @State private var viewModel: FeedViewModel
    @Environment(\.blueskyTheme) private var theme

    public init(
        network: any NetworkClient,
        accountStore: any AccountStore,
        cache: any CacheStore,
        onVideoTap: @escaping (PostView) -> Void,
        onViewMoreTap: (() -> Void)? = nil
    ) {
        _viewModel = State(
            initialValue: FeedViewModel(
                network: network,
                accountStore: accountStore,
                cache: cache,
                selection: .feed(uri: VideoFeedView.videoFeedURI)
            )
        )
        self.onVideoTap = onVideoTap
        self.onViewMoreTap = onViewMoreTap
    }

    /// First `maxCards` posts carrying a direct video embed, mirroring RN's
    /// `filter(item => AppBskyEmbedVideo.isView(item.post.embed)).slice(0, 8)`.
    private var videoPosts: [PostView] {
        viewModel.posts
            .map(\.post)
            .filter { post in
                if case .video = post.embed { return true }
                return false
            }
            .prefix(Self.maxCards)
            .map { $0 }
    }

    /// Whether the initial fetch has completed (success or failure).
    @State private var didLoad = false

    public var body: some View {
        Group {
            // RN returns null on error; likewise collapse when the load
            // finished without any video posts so the section never renders
            // an empty rail. Until the fetch completes, render the
            // placeholder rail (RN shows placeholders while loading).
            if didLoad && videoPosts.isEmpty {
                EmptyView()
            } else {
                content
            }
        }
        // Attached outside `content` so the fetch starts even though the
        // first render happens before any posts exist.
        .task {
            guard !didLoad else { return }
            await viewModel.loadInitial()
            didLoad = true
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — RN: gutters + pb_sm, small semibold title.
            Text("Trending Videos")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.colors.textPrimary)
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.sm)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Spacing.md) {
                    if viewModel.isLoading && videoPosts.isEmpty {
                        ForEach(0..<6, id: \.self) { _ in
                            cardPlaceholder
                        }
                    } else {
                        ForEach(videoPosts, id: \.uri) { post in
                            if case .video(let video) = post.embed {
                                CompactVideoCard(
                                    post: post,
                                    video: video,
                                    width: Self.cardWidth,
                                    height: Self.cardHeight,
                                    onTap: { onVideoTap(post) }
                                )
                            }
                        }
                        if let onViewMoreTap {
                            viewMoreCard(action: onViewMoreTap)
                        }
                    }
                }
                .padding(.horizontal, Spacing.lg)
            }
        }
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.lg)
        .background(theme.colors.backgroundSecondary)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(theme.colors.border)
                .frame(height: 0.5)
        }
        .accessibilityIdentifier("trending-videos-interstitial")
    }

    private var cardPlaceholder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(theme.colors.backgroundSecondary)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(theme.colors.border, lineWidth: 0.5)
            )
            .frame(width: Self.cardWidth, height: Self.cardHeight)
    }

    /// Trailing "View more" card — RN `ViewMoreCard`: a `CARD_WIDTH * 2` wide
    /// bordered card with "View more" text and a round blue chevron button,
    /// navigating to the video feed generator's timeline.
    private func viewMoreCard(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                Text("View more")
                    .font(.body)
                    .foregroundStyle(theme.colors.textPrimary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(theme.colors.link, in: Circle())
            }
            .frame(width: Self.cardWidth * 2, height: Self.cardHeight)
            .background(theme.colors.background)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(theme.colors.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("View more trending videos")
        .accessibilityIdentifier("trending-videos-view-more")
    }
}

// MARK: - CompactVideoCard

/// SwiftUI port of RN's `CompactVideoPostCard`: a 9:16 thumbnail card with the
/// author's avatar pinned top-leading. The like-count gradient footer is
/// omitted — RN ships with `showLikeCount = false` at the baseline commit.
private struct CompactVideoCard: View {
    let post: PostView
    let video: EmbedVideoView
    let width: CGFloat
    let height: CGFloat
    let onTap: () -> Void

    @Environment(\.blueskyTheme) private var theme

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topLeading) {
                Color.black

                if let thumbnail = video.thumbnail {
                    AsyncImage(url: thumbnail) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            Color.black
                        }
                    }
                }

                AvatarView(
                    url: post.author.avatar,
                    handle: post.author.handle.rawValue,
                    size: 24
                )
                .padding(Spacing.sm)
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(theme.colors.border, lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Video from \(post.author.handle.rawValue)")
        .accessibilityIdentifier("trending-video-card")
        .help("Views video in immersive mode")
    }
}
