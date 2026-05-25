import SwiftUI
import OSLog
import BlueskyCore
import BlueskyKit
import BlueskyUI
import BlueskyComposer

private let profileScreenLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "co.sstools.Bluesky", category: "ProfileScreen")

/// Full-page profile view: banner + avatar header, tab strip, post feed.
public struct ProfileScreen: View {

    private let network: any NetworkClient
    private let accountStore: any AccountStore
    private let viewerDID: DID?
    /// Optional own-profile menu actions surfaced via the in-screen ellipsis
    /// next to "Edit Profile" on iOS (#0083). On macOS the toolbar Menu in
    /// `MainTabView` keeps owning these.
    private let onSettings: (() -> Void)?
    private let onSaved: (() -> Void)?
    private let onMyLists: (() -> Void)?
    private let onModeration: (() -> Void)?

    @Environment(\.blueskyTheme) private var theme
    @State private var viewModel: ProfileViewModel
    @State private var selectedTab: ProfileTab = .posts
    @State private var showEditProfile = false
    @State private var threadURI: ATURI?
    @State private var updateProfileErrorMessage: String?

    // #0159: per-post action targets — drive the reply / repost-or-quote
    // confirmation dialog the same way `FeedView` does on the home tab. Kept
    // local to `ProfileScreen` because BlueskyProfile cannot import
    // BlueskyFeed without forming a Layer-3 ↔ Layer-3 cycle.
    @State private var replyTarget: PostView?
    @State private var repostMenuTarget: PostView?
    @State private var quoteTarget: PostView?

    public init(
        actorDID: DID,
        network: any NetworkClient,
        accountStore: any AccountStore,
        viewerDID: DID? = nil,
        onSettings: (() -> Void)? = nil,
        onSaved: (() -> Void)? = nil,
        onMyLists: (() -> Void)? = nil,
        onModeration: (() -> Void)? = nil
    ) {
        self.network = network
        self.accountStore = accountStore
        self.viewerDID = viewerDID
        self.onSettings = onSettings
        self.onSaved = onSaved
        self.onMyLists = onMyLists
        self.onModeration = onModeration
        _viewModel = State(wrappedValue: ProfileViewModel(
            network: network,
            accountStore: accountStore,
            actorDID: actorDID
        ))
    }

    public var body: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    feedContent
                } header: {
                    VStack(spacing: 0) {
                        profileHeader
                        tabStrip
                    }
                    .background(theme.colors.background)
                }
            }
        }
        // #0155: do NOT apply `.ignoresSafeArea(edges: .top)` to this ScrollView.
        // It used to live here from #0088 to let the banner bleed behind the
        // status bar, but inside the iPhone compact `NavigationStack` (which is
        // wrapped in a `safeAreaInset(edge: .top)` carrying an `EmptyView` on
        // the Profile tab — see `MainTabView.iosCompactLayout`), `.ignoresSafeArea`
        // here was leaking horizontally and pulling the LazyVStack ~16pt off the
        // leading edge. Every text line, the avatar, and the tab strip all
        // shifted left, clipping their first character / partial avatar / the
        // Feeds tab. Instead, the bleed-up is now owned by `ProfileHeaderView`'s
        // `bannerSection` via a `GeometryReader`-based negative top padding —
        // see the comment there.
        // UI-test coupling surface (#0178): identifies the whole profile page so
        // the suite can assert `profile-screen` exists after a feed author tap
        // pushes another user's profile, and that it's gone after back nav.
        // `children: .contain` keeps the nested header elements, tab buttons,
        // and post cells individually addressable.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile-screen")
        .refreshable {
            await viewModel.loadProfile()
            await loadCurrentTab(selectedTab)
        }
        .adaptiveBlueskyTheme()
        #if os(iOS)
        // #0083: drop the giant "brennan.sstools.co" headline. RN renders
        // nothing above the banner, so hide the navigation bar entirely on
        // iOS. macOS keeps its window title via `.navigationTitle` below.
        // Inline-on-scroll polish was skipped — the banner stays unannounced.
        .toolbar(.hidden, for: .navigationBar)
        #else
        .navigationTitle(viewModel.profile?.handle.rawValue ?? "Profile")
        #endif
        .task {
            await viewModel.loadProfile()
            await loadCurrentTab(selectedTab)
        }
        .onChange(of: selectedTab) { _, newTab in
            Task { await loadCurrentTab(newTab) }
        }
        .navigationDestination(isPresented: Binding(
            get: { threadURI != nil },
            set: { if !$0 { threadURI = nil } }
        )) {
            if let uri = threadURI {
                ThreadPlaceholder(uri: uri)
            }
        }
        .sheet(isPresented: $showEditProfile) {
            if let profile = viewModel.profile {
                EditProfileSheet(
                    displayName: profile.displayName ?? "",
                    description: profile.description ?? "",
                    onSave: { name, desc in
                        Task {
                            do {
                                try await viewModel.updateProfile(displayName: name, description: desc)
                            } catch {
                                profileScreenLogger.error("updateProfile failed: \(error.localizedDescription, privacy: .public)")
                                await MainActor.run {
                                    updateProfileErrorMessage = error.localizedDescription
                                }
                            }
                        }
                    }
                )
            }
        }
        .alert("Could not update profile",
               isPresented: Binding(
                    get: { updateProfileErrorMessage != nil },
                    set: { if !$0 { updateProfileErrorMessage = nil } }
               )
        ) {
            Button("OK") { updateProfileErrorMessage = nil }
        } message: {
            Text(updateProfileErrorMessage ?? "")
        }
        // #0159: reply composer for post rows on Profile tabs.
        .sheet(isPresented: Binding(
            get: { replyTarget != nil },
            set: { if !$0 { replyTarget = nil } }
        )) {
            if let post = replyTarget {
                ComposerSheet(
                    network: network,
                    accountStore: accountStore,
                    replyTo: PostRef(uri: post.uri, cid: post.cid),
                    replyToView: post
                )
            }
        }
        // #0159: quote-post composer, opened from the repost confirmation dialog.
        .sheet(isPresented: Binding(
            get: { quoteTarget != nil },
            set: { if !$0 { quoteTarget = nil } }
        )) {
            if let post = quoteTarget {
                ComposerSheet(
                    network: network,
                    accountStore: accountStore,
                    quotedPost: PostRef(uri: post.uri, cid: post.cid),
                    quotedPostView: post
                )
            }
        }
        // #0159: Repost / Quote chooser, mirrors `FeedView`'s confirmation
        // dialog. Shown only when the post is not yet reposted; the toggle
        // path in `postActions(for:)` handles the unrepost case directly.
        .confirmationDialog("", isPresented: Binding(
            get: { repostMenuTarget != nil },
            set: { if !$0 { repostMenuTarget = nil } }
        ), titleVisibility: .hidden) {
            Button("Repost") {
                guard let post = repostMenuTarget else { return }
                repostMenuTarget = nil
                Task { await viewModel.toggleRepost(post: post) }
            }
            Button("Quote Post") {
                quoteTarget = repostMenuTarget
                repostMenuTarget = nil
            }
            Button("Cancel", role: .cancel) {
                repostMenuTarget = nil
            }
        }
    }

    // MARK: - Header

    private var profileHeader: some View {
        ProfileHeaderView(
            profile: viewModel.profile,
            isOwnProfile: viewModel.actorDID == viewerDID,
            knownFollowers: viewModel.knownFollowers,
            onFollow:      { Task { await viewModel.follow() } },
            onUnfollow:    { Task { await viewModel.unfollow() } },
            onBlock:       { Task { await viewModel.block() } },
            onUnblock:     { Task { await viewModel.unblock() } },
            onMute:        { Task { await viewModel.mute() } },
            onUnmute:      { Task { await viewModel.unmute() } },
            onEditProfile: { showEditProfile = true },
            onSettings:    onSettings,
            onSaved:       onSaved,
            onMyLists:     onMyLists,
            onModeration:  onModeration
        )
    }

    // MARK: - Tab strip

    /// Profile tab strip per #0086:
    ///  - Seven tabs in RN order: Posts · Replies · Media · Videos · Likes · Feeds · Lists.
    ///  - Inline rendering with no surrounding pill capsule.
    ///  - 2pt brand-color underline on the selected tab via `UnderlineTabStrip`
    ///    (shared visual treatment with the Home feed strip from #0074).
    ///  - Horizontally scrollable since seven tabs don't fit on iPhone widths.
    private var tabStrip: some View {
        UnderlineTabStrip(
            tabs: ProfileTab.allCases.map { UnderlineTab(id: $0.rawValue, label: $0.title) },
            selectedID: Binding(
                get: { selectedTab.rawValue },
                set: { newID in
                    if let tab = ProfileTab(rawValue: newID) {
                        selectedTab = tab
                    }
                }
            ),
            // UI-test coupling surface (#0178): tags each profile tab as
            // `profile-<id>-tab` (e.g. `profile-posts-tab`) so the suite can
            // assert the Posts tab exists and is selected by default.
            accessibilityIDPrefix: "profile"
        )
    }

    // MARK: - Tab loading

    private func loadCurrentTab(_ tab: ProfileTab) async {
        switch tab {
        case .feeds:
            await viewModel.loadFeeds()
        case .lists:
            await viewModel.loadLists()
        default:
            await viewModel.loadFeed(tab: tab)
        }
    }

    // MARK: - Feed content

    @ViewBuilder
    private var feedContent: some View {
        switch selectedTab {
        case .feeds:
            feedsTabContent
        case .lists:
            listsTabContent
        default:
            postsTabContent
        }
    }

    @ViewBuilder
    private var postsTabContent: some View {
        let posts = viewModel.posts(for: selectedTab)
        if posts.isEmpty && viewModel.isLoadingFeed(for: selectedTab) {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(40)
        } else if posts.isEmpty {
            Text(emptyMessage(for: selectedTab))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(40)
        } else {
            ForEach(posts, id: \.post.uri) { item in
                PostCard(item: item, actions: postActions(for: item))
                Divider()
                    .onAppear {
                        if item.post.uri == posts.last?.post.uri {
                            Task { await viewModel.loadMoreFeed(tab: selectedTab) }
                        }
                    }
            }
            if viewModel.isLoadingFeed(for: selectedTab) {
                HStack { Spacer(); ProgressView(); Spacer() }.padding()
            }
        }
    }

    @ViewBuilder
    private var feedsTabContent: some View {
        if viewModel.actorFeeds.isEmpty {
            Text("No feeds")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(40)
        } else {
            ForEach(viewModel.actorFeeds, id: \.uri) { feed in
                FeedCard(feed: feed)
                Divider()
            }
        }
    }

    @ViewBuilder
    private var listsTabContent: some View {
        if viewModel.actorLists.isEmpty {
            Text("No lists")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(40)
        } else {
            ForEach(viewModel.actorLists, id: \.uri) { list in
                ListCard(list: list)
                Divider()
            }
        }
    }

    /// Wire up the per-post action callbacks the same way `FeedView` does for
    /// the home feed (#0159). Reply / repost-or-quote are routed through the
    /// local sheet/confirmation dialog state above; like, repost-via-toggle
    /// (when already reposted), and bookmark go straight to the view model's
    /// optimistic-update mutation methods. Share and the ellipsis menu are
    /// fully owned by `PostCard` itself — `ShareLink` and the system `Menu` —
    /// so they don't need callbacks here.
    private func postActions(for item: FeedViewPost) -> PostCard.Actions {
        var a = PostCard.Actions()
        a.onTap = { post in threadURI = post.uri }
        a.onReply = { post in replyTarget = post }
        a.onLike = { post in
            // Use the freshest local snapshot as the basis so a re-render
            // between tap and dispatch doesn't cause us to act on a stale
            // viewer state. Mirrors `FeedView.actions(for:vm:)`.
            let current = viewModel.posts(for: selectedTab)
                .first(where: { $0.post.uri == post.uri })?.post ?? post
            Task { await viewModel.toggleLike(post: current) }
        }
        a.onRepost = { post in
            let current = viewModel.posts(for: selectedTab)
                .first(where: { $0.post.uri == post.uri })?.post ?? post
            // If the post is already reposted, jump straight to unrepost.
            // Otherwise show the Repost / Quote chooser.
            if current.viewer?.repost != nil {
                Task { await viewModel.toggleRepost(post: current) }
            } else {
                repostMenuTarget = current
            }
        }
        a.isBookmarked = item.post.viewer?.bookmarked ?? false
        a.onBookmark = { post in Task { await viewModel.bookmark(post: post) } }
        return a
    }

    /// Tab-specific empty-state copy. The strings stay short and friendly to
    /// match the existing "No posts" / "No feeds" / "No lists" voice.
    private func emptyMessage(for tab: ProfileTab) -> String {
        switch tab {
        case .posts:   "No posts"
        case .replies: "No replies"
        case .media:   "No media"
        case .videos:  "No videos yet"
        case .likes:   "No likes"
        case .feeds, .lists: ""
        }
    }
}

// MARK: - Thread placeholder (avoids circular dependency on BlueskyFeed)

private struct ThreadPlaceholder: View {
    let uri: ATURI
    var body: some View {
        Text("Thread: \(uri.rawValue)")
            .navigationTitle("Thread")
    }
}

// MARK: - Preview helpers

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

// MARK: - Previews

#Preview("ProfileScreen — Light") {
    NavigationStack {
        ProfileScreen(
            actorDID: DID(rawValue: "did:plc:alice"),
            network: PreviewNoOpNetwork(),
            accountStore: PreviewNoOpAccountStore()
        )
    }
    .preferredColorScheme(.light)
}

#Preview("ProfileScreen — Dark") {
    NavigationStack {
        ProfileScreen(
            actorDID: DID(rawValue: "did:plc:alice"),
            network: PreviewNoOpNetwork(),
            accountStore: PreviewNoOpAccountStore()
        )
    }
    .preferredColorScheme(.dark)
}
