import AVKit
import SwiftUI
import BlueskyCore
import BlueskyKit
import BlueskyUI

private final class PreviewNoOpNetwork: NetworkClient, @unchecked Sendable {
    nonisolated func get<R: Decodable & Sendable>(lexicon: String, params: [String: String]) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func post<B: Encodable & Sendable, R: Decodable & Sendable>(lexicon: String, body: B) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func upload<R: Decodable & Sendable>(lexicon: String, data: Data, mimeType: String) async throws -> R { throw ATError.unknown("preview") }
}

private final class PreviewNoOpAccountStore: AccountStore, @unchecked Sendable {
    nonisolated func save(_ account: StoredAccount) async throws {}
    nonisolated func loadAll() async throws -> [StoredAccount] { [] }
    nonisolated func load(did: DID) async throws -> StoredAccount? { nil }
    nonisolated func remove(did: DID) async throws {}
    nonisolated func setCurrentDID(_ did: DID?) async throws {}
    nonisolated func loadCurrentDID() async throws -> DID? { nil }
}

private final class PreviewNoOpCache: CacheStore, @unchecked Sendable {
    nonisolated func store<T: Codable & Sendable>(_ value: T, for key: String, ttl: TimeInterval?) async throws {}
    nonisolated func fetch<T: Codable & Sendable>(_ type: T.Type, for key: String) async throws -> CacheResult<T>? { nil }
    nonisolated func evict(for key: String) async throws {}
    nonisolated func evictAll() async throws {}
}

/// Full-screen vertical-scroll video feed backed by a video algorithm feed generator.
public struct VideoFeedView: View {
    /// AT-URI of Bluesky's video algorithm feed generator (`thevids`).
    /// RN parity: `VIDEO_FEED_URI` in `Bluesky-ReactNative/src/lib/constants.ts`
    /// — the source feed for the immersive VideoFeed screen and the
    /// Trending Videos interstitial (#0205).
    public static let videoFeedURI =
        "at://did:plc:z72i7hdynmk6r22z27h6tvur/app.bsky.feed.generator/thevids"

    @State private var viewModel: FeedViewModel
    @State private var currentIndex = 0
    /// Per-session mute preference. Mirrors the RN immersive-video behaviour
    /// where the mute state is sticky across pages until the user toggles it.
    @State private var isMuted = true
    /// Autoplay preference, threaded down from the parent. Defaults to true
    /// so the video feed plays even when the parent doesn't inject a value.
    private let autoplay: Bool
    /// Tap-the-author callbacks. The video feed page surfaces an avatar/handle
    /// row in the bottom-left and a comments button in the right-edge stack —
    /// both navigate, and the parent owns the navigation stack.
    private let onProfileTap: ((DID) -> Void)?
    private let onPostTap: ((PostView) -> Void)?
    /// AT-URI of the post the pager should open on. RN parity: the
    /// `VideoFeed` route's `initialPostUri` param — entry points (video
    /// cards in the Trending Videos rail) seed the feed at the tapped post.
    private let initialPostURI: String?

    public init(
        network: any NetworkClient,
        accountStore: any AccountStore,
        cache: any CacheStore,
        feedURI: String,
        initialPostURI: String? = nil,
        autoplay: Bool = true,
        onProfileTap: ((DID) -> Void)? = nil,
        onPostTap: ((PostView) -> Void)? = nil
    ) {
        _viewModel = State(
            initialValue: FeedViewModel(
                network: network,
                accountStore: accountStore,
                cache: cache,
                selection: .feed(uri: feedURI)
            )
        )
        self.initialPostURI = initialPostURI
        self.autoplay = autoplay
        self.onProfileTap = onProfileTap
        self.onPostTap = onPostTap
    }

    private var videoPosts: [FeedViewPost] {
        viewModel.posts.filter { post in
            if case .video = post.post.embed { return true }
            return false
        }
    }

    public var body: some View {
        Group {
            if viewModel.isLoading && videoPosts.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if videoPosts.isEmpty && !viewModel.isLoading {
                ContentUnavailableView(
                    "No Videos",
                    systemImage: "video.slash",
                    description: Text("No video posts found in this feed.")
                )
            } else {
                videoScrollView
            }
        }
        .task {
            await viewModel.loadInitial()
            // Seed the pager at the tapped post (RN: `initialPostUri`).
            // Only video-embed posts get pages, so resolve the index against
            // the filtered list; missing posts fall back to page 0.
            if let initialPostURI,
               let index = videoPosts.firstIndex(where: { $0.post.uri.rawValue == initialPostURI }) {
                currentIndex = index
            }
        }
        // #0205: UI-test anchor for the immersive video feed surface.
        .accessibilityIdentifier("video-feed-screen")
        .navigationTitle("Video")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var videoScrollView: some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(videoPosts.enumerated()), id: \.element.post.uri) { index, feedPost in
                if case .video(let video) = feedPost.post.embed {
                    VideoPostPage(
                        feedPost: feedPost,
                        video: video,
                        viewModel: viewModel,
                        isMuted: $isMuted,
                        autoplay: autoplay,
                        onProfileTap: onProfileTap,
                        onPostTap: onPostTap
                    )
                    .tag(index)
                    .onAppear {
                        if index >= videoPosts.count - 2 {
                            Task { await viewModel.loadMore() }
                        }
                    }
                }
            }
        }
        #if os(iOS)
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
        #endif
    }
}

// MARK: - VideoPostPage

private struct VideoPostPage: View {
    let feedPost: FeedViewPost
    let video: EmbedVideoView
    /// Reference to the shared feed view model so per-page like / repost taps
    /// flow through the existing optimistic-update path used by the regular
    /// feed (`FeedViewModel.toggleLike` / `toggleRepost`).
    let viewModel: FeedViewModel
    @Binding var isMuted: Bool
    let autoplay: Bool
    let onProfileTap: ((DID) -> Void)?
    let onPostTap: ((PostView) -> Void)?

    @State private var player: AVPlayer?
    @State private var isShowingInfo = false
    @State private var isPlaying = false
    @State private var progress: Double = 0
    /// Briefly shown after a tap toggles play/pause, mirroring the RN
    /// "tap-to-pause" visual feedback.
    @State private var showPlayPauseIndicator = false
    @State private var playPauseIndicatorWorkItem: DispatchWorkItem?
    /// Token returned by `addPeriodicTimeObserver`; must be passed back to
    /// `removeTimeObserver` on disappear or the player will retain the
    /// observer (and the closure capturing self) past the view's lifetime.
    @State private var timeObserverToken: Any?

    /// Token returned by the block-based `addObserver(forName:…)` for the
    /// loop (`AVPlayerItemDidPlayToEndTime`) observer. The block API registers
    /// an internal opaque object, NOT `self`, so it must be removed via this
    /// token — the previous `removeObserver(self as Any, …)` was a no-op and
    /// leaked one observer (and its closure) per page swiped (#0223).
    @State private var endObserverToken: (any NSObjectProtocol)?

    /// Live snapshot of the post from the view model — drives like/repost
    /// counts so the optimistic update from `toggleLike(_:)` shows up here
    /// without re-routing the whole feed.
    private var currentPost: PostView {
        viewModel.posts.first(where: { $0.post.uri == feedPost.post.uri })?.post
            ?? feedPost.post
    }

    private var isLiked: Bool { currentPost.viewer?.like != nil }
    private var isReposted: Bool { currentPost.viewer?.repost != nil }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                // No controls: the surface doesn't hit-test, so the
                // tap-to-pause layer below wins.
                BlueskyVideoView(player: player)
                    .ignoresSafeArea()
            }

            // Tap-to-play/pause hit area covers the full bounds but sits
            // beneath the action overlays (which have higher z-order).
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { togglePlayPause() }

            if showPlayPauseIndicator {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 6)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }

            overlayContent
        }
        .onAppear { setUpPlayer() }
        .onDisappear { tearDownPlayer() }
        .onChange(of: isMuted) { _, newValue in
            player?.isMuted = newValue
        }
    }

    // MARK: Overlays

    private var overlayContent: some View {
        VStack(spacing: 0) {
            // Top bar — mute toggle pinned top-trailing.
            HStack {
                Spacer()
                Button {
                    isMuted.toggle()
                } label: {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(.black.opacity(0.45), in: Circle())
                }
                .buttonStyle(.plain)
                .help(isMuted ? "Unmute" : "Mute")
                .padding(.top, 12)
                .padding(.trailing, 12)
            }

            Spacer(minLength: 0)

            // Bottom row — author/text on the left, action stack on the right.
            HStack(alignment: .bottom, spacing: Spacing.sm) {
                authorAndCaption
                    .frame(maxWidth: .infinity, alignment: .leading)
                actionStack
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.sm)

            scrubber
        }
    }

    private var authorAndCaption: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Button {
                onProfileTap?(currentPost.author.did)
            } label: {
                HStack(spacing: Spacing.sm) {
                    AvatarView(
                        url: currentPost.author.avatar,
                        handle: currentPost.author.handle.rawValue,
                        size: 36
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        if let name = currentPost.author.displayName {
                            Text(name)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                        Text("@\(currentPost.author.handle.rawValue)")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)

            if !currentPost.record.text.isEmpty {
                Text(currentPost.record.text)
                    .foregroundStyle(.white)
                    .lineLimit(isShowingInfo ? nil : 2)
                    .onTapGesture { isShowingInfo.toggle() }
            }

            if let alt = video.alt, !alt.isEmpty, isShowingInfo {
                Text("Alt: \(alt)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(Spacing.sm)
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// Right-edge action stack — order matches the RN PostControls layout in
    /// `Bluesky-ReactNative/src/components/PostControls/`: reply, repost,
    /// like, share. We fold "comments / reply" into the entry that opens the
    /// thread because the immersive video feed has no inline reply composer.
    private var actionStack: some View {
        VStack(spacing: Spacing.lg) {
            actionButton(
                icon: "bubble.left",
                count: currentPost.replyCount,
                tint: .white,
                help: "Comments"
            ) {
                onPostTap?(currentPost)
            }

            actionButton(
                icon: isReposted ? "arrow.2.squarepath" : "arrow.2.squarepath",
                count: currentPost.repostCount,
                tint: isReposted ? .green : .white,
                help: isReposted ? "Undo repost" : "Repost"
            ) {
                let snapshot = currentPost
                Task { await viewModel.toggleRepost(post: snapshot) }
            }

            actionButton(
                icon: isLiked ? "heart.fill" : "heart",
                count: currentPost.likeCount,
                tint: isLiked ? .pink : .white,
                help: isLiked ? "Unlike" : "Like"
            ) {
                let snapshot = currentPost
                Task { await viewModel.toggleLike(post: snapshot) }
            }

            if let url = shareURL(for: currentPost) {
                ShareLink(item: url) {
                    actionGlyph(icon: "square.and.arrow.up", count: nil, tint: .white)
                }
                .buttonStyle(.plain)
                .help("Share")
            }
        }
    }

    private func actionButton(
        icon: String,
        count: Int?,
        tint: Color,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            actionGlyph(icon: icon, count: count, tint: tint)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func actionGlyph(icon: String, count: Int?, tint: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(tint)
                .shadow(color: .black.opacity(0.5), radius: 2)
            if let count, count > 0 {
                Text(formatCount(count))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 2)
            }
        }
        .frame(width: 44)
    }

    private var scrubber: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.25))
                Rectangle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: proxy.size.width * progress)
            }
        }
        .frame(height: 2)
    }

    // MARK: Player lifecycle

    private func setUpPlayer() {
        let p = AVPlayer(url: video.playlist)
        p.isMuted = isMuted
        if autoplay {
            p.play()
            isPlaying = true
        } else {
            isPlaying = false
        }
        // Loop playback — RN's expo-video sets `player.loop = true`; on AVPlayer
        // we re-seek to zero on the AVPlayerItem `didPlayToEndTime` notification.
        if let item = p.currentItem {
            endObserverToken = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak p] _ in
                p?.seek(to: .zero)
                p?.play()
            }
        }

        // Periodic time observer to drive the scrubber. 10 Hz is enough for a
        // thin progress bar without burning the main thread.
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        let token = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            guard let duration = p.currentItem?.duration.seconds, duration.isFinite, duration > 0 else {
                return
            }
            let current = time.seconds
            let next = min(max(current / duration, 0), 1)
            // The observer runs on `.main` so we hop onto MainActor to satisfy
            // strict-concurrency: SwiftUI `@State` mutations must be isolated.
            Task { @MainActor in
                progress = next
            }
        }
        timeObserverToken = token
        player = p
    }

    private func tearDownPlayer() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        if let token = endObserverToken {
            NotificationCenter.default.removeObserver(token)
            endObserverToken = nil
        }
        player?.pause()
        player = nil
        isPlaying = false
    }

    private func togglePlayPause() {
        guard let player else { return }
        if player.timeControlStatus == .playing {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
        // Briefly flash the play / pause indicator to mirror the RN tap
        // feedback. Cancel any in-flight reset so rapid taps don't leave
        // the icon stuck on screen.
        playPauseIndicatorWorkItem?.cancel()
        withAnimation(.easeInOut(duration: 0.15)) {
            showPlayPauseIndicator = true
        }
        let workItem = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.25)) {
                showPlayPauseIndicator = false
            }
        }
        playPauseIndicatorWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: workItem)
    }

    // MARK: Helpers

    private func shareURL(for post: PostView) -> URL? {
        let handle = post.author.handle.rawValue
        let rkey = post.uri.rawValue.components(separatedBy: "/").last ?? ""
        guard !rkey.isEmpty else { return nil }
        return URL(string: "https://bsky.app/profile/\(handle)/post/\(rkey)")
    }

    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

// MARK: - Previews

private let previewVideoFeedURI = VideoFeedView.videoFeedURI

#Preview("VideoFeedView — Light") {
    NavigationStack {
        VideoFeedView(
            network: PreviewNoOpNetwork(),
            accountStore: PreviewNoOpAccountStore(),
            cache: PreviewNoOpCache(),
            feedURI: previewVideoFeedURI
        )
    }
    .preferredColorScheme(.light)
}

#Preview("VideoFeedView — Dark") {
    NavigationStack {
        VideoFeedView(
            network: PreviewNoOpNetwork(),
            accountStore: PreviewNoOpAccountStore(),
            cache: PreviewNoOpCache(),
            feedURI: previewVideoFeedURI
        )
    }
    .preferredColorScheme(.dark)
}
