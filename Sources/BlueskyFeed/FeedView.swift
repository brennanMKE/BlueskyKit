import OSLog
import SwiftUI
import BlueskyCore
import BlueskyKit
import BlueskyUI
import BlueskyComposer

nonisolated private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "co.sstools.Bluesky",
    category: "FeedView"
)

// MARK: - SavedFeedsChanged notification

/// Posted by `MyFeedsScreen` whenever the user's saved-feed list is mutated
/// and persisted (pin/unpin, add suggested, reorder, …). `FeedView` listens
/// so the Home tab strip can re-pick up the latest pinned set without forcing
/// the user to re-enter the screen. The object is `nil` because the strip
/// reloads from `SavedFeedsStore` on receipt.
public extension Foundation.Notification.Name {
    static let savedFeedsChanged = Foundation.Notification.Name(
        "co.sstools.bluesky.savedFeedsChanged"
    )
}

// MARK: - FeedViewModelCache

/// Reference-type wrapper around the per-selection `FeedViewModel` dictionary.
///
/// Storing this as `@State` inside `FeedView` means SwiftUI keeps the *same
/// object* alive even when the view struct is re-initialised by its parent
/// (which happens during auth-state re-renders in `MainTabView`).  A plain
/// value-type dictionary would reset to `[:]` on every re-init, causing
/// duplicate `FeedViewModel` creation and two concurrent network fetches
/// (issue #0049).
final class FeedViewModelCache {
    private var storage: [FeedSelection: FeedViewModel] = [:]

    subscript(selection: FeedSelection) -> FeedViewModel? {
        get { storage[selection] }
        set { storage[selection] = newValue }
    }
}

// MARK: - FeedView

/// The home feed view — scrollable tab strip at the top, swipeable per-tab
/// timelines below.
///
/// The strip lists four built-in tabs (Following · Mentions · Discover ·
/// Popular With Friends) followed by every feed the user has pinned in
/// preferences. Pinned-feed list comes from the same `SavedFeedsStore` the
/// My Feeds screen uses (#0073) and refreshes whenever the screen posts
/// `Notification.Name.savedFeedsChanged` after a successful `putPreferences`.
public struct FeedView: View {

    private let network: any NetworkClient
    private let accountStore: any AccountStore
    private let cache: any CacheStore
    private let bookmarks: (any BookmarkStoring)?
    var onPostTap: ((PostView) -> Void)?
    var onAuthorTap: ((ProfileBasic) -> Void)?

    /// Injected from boot() via SwiftUI environment. When present, FeedView uses this
    /// store for .timeline instead of creating a new one, so the initial load is never
    /// tied to a SwiftUI .task that can be cancelled by view recreation.
    @Environment(FeedStore.self) private var bootTimelineStore: FeedStore

    public init(
        network: any NetworkClient,
        accountStore: any AccountStore,
        cache: any CacheStore,
        bookmarks: (any BookmarkStoring)? = nil,
        onPostTap: ((PostView) -> Void)? = nil,
        onAuthorTap: ((ProfileBasic) -> Void)? = nil
    ) {
        self.network = network
        self.accountStore = accountStore
        self.cache = cache
        self.bookmarks = bookmarks
        self.onPostTap = onPostTap
        self.onAuthorTap = onAuthorTap
    }

    /// ID of the active tab in `tabs`. Driving the pager off an `id` rather
    /// than an integer index lets us insert / remove pinned feeds without
    /// jolting the active selection — if the user is on Discover and adds a
    /// new pinned feed, the index would shift but the ID does not.
    @State private var selectedTabID: String = HomeFeedTab.following.id

    /// Pinned-feed metadata. Loaded once on appear and refreshed whenever
    /// `MyFeedsScreen` posts `savedFeedsChanged`, so the strip mirrors the
    /// user's saved-feed set live (#0074 acceptance).
    @State private var savedFeedsStore: SavedFeedsStore?

    /// Wrapped in a reference-type box so that SwiftUI preserves the same
    /// dictionary even when `FeedView` is reconstructed by its parent (e.g.
    /// during auth-state re-renders in `MainTabView`).  A plain
    /// `@State var [FeedSelection: FeedViewModel]` resets to `[:]` every time
    /// the struct is re-initialised, which causes a fresh `.task(id:)` to fire
    /// and a duplicate `FeedViewModel` to be created (issue #0049).
    @State private var vmCache = FeedViewModelCache()
    @State private var filter: FeedFilter = FeedFilter()
    @State private var replyTarget: PostView? = nil
    @State private var repostMenuTarget: PostView? = nil
    @State private var repostTargetVM: FeedViewModel? = nil
    @State private var quoteTarget: PostView? = nil

    /// Built-in tabs plus the user's pinned feeds, in the order they should
    /// appear in the strip (built-ins first, pinned in their saved order).
    private var tabs: [HomeFeedTab] {
        let pinned = (savedFeedsStore?.feeds ?? [])
            .filter { $0.pinned && $0.type == "feed" }
            // Skip any pinned feed whose URI matches a built-in — keeps the
            // strip tidy when the user has pinned (e.g.) Discover from the
            // suggested list.
            .filter { saved in
                !HomeFeedTab.builtIns.contains(where: {
                    if case .feed(let uri) = $0.selection { return uri == saved.value }
                    return false
                })
            }
            .map { saved -> HomeFeedTab in
                HomeFeedTab.pinned(
                    displayName: pinnedFeedDisplayName(saved),
                    uri: saved.value
                )
            }
        return HomeFeedTab.builtIns + pinned
    }

    public var body: some View {
        VStack(spacing: 0) {
            FeedSwitcherView(
                tabs: tabs,
                selectedID: $selectedTabID
            )
            Divider()
            // TODO #0017: the hide-replies / hide-reposts filter controls
            // previously lived in a dropdown next to the tab strip. They are
            // dropped from this position to match the RN reference (the strip
            // is now the only thing on this row). When the filter feature is
            // re-introduced it should move under each tab's per-feed
            // ellipsis / overflow menu rather than the global header.
            pager
        }
        #if os(macOS)
        .navigationTitle("Home")
        #else
        // iOS top chrome is owned by the parent — `MainTabView` wraps the
        // compact iPhone layout in a `BlueskyTopBar` and hides the system
        // navigation bar; iPad regular keeps the nav bar but uses inline
        // display mode so we don't get the giant "Home" headline.
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .adaptiveBlueskyTheme()
        .task {
            // Lazy-create the saved-feeds store so we share `cache` from init
            // without forcing every preview to provide one.
            if savedFeedsStore == nil {
                savedFeedsStore = SavedFeedsStore(network: network, cache: cache)
            }
            await savedFeedsStore?.load()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .savedFeedsChanged)
        ) { _ in
            Task { await savedFeedsStore?.load() }
        }
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
        .confirmationDialog("", isPresented: Binding(
            get: { repostMenuTarget != nil },
            set: { if !$0 { repostMenuTarget = nil; repostTargetVM = nil } }
        ), titleVisibility: .hidden) {
            Button("Repost") {
                guard let post = repostMenuTarget, let vm = repostTargetVM else { return }
                repostMenuTarget = nil
                repostTargetVM = nil
                Task { await vm.repost(post: post) }
            }
            Button("Quote Post") {
                quoteTarget = repostMenuTarget
                repostMenuTarget = nil
                repostTargetVM = nil
            }
            Button("Cancel", role: .cancel) {
                repostMenuTarget = nil
                repostTargetVM = nil
            }
        }
    }

    // MARK: - Pager

    /// Swipeable per-tab timeline pager.
    ///
    /// On iOS we use `TabView` with `.page` style so the user can swipe
    /// horizontally between adjacent tabs and the system handles the gesture
    /// + animation. macOS `TabView` doesn't support page-style swiping, so
    /// we fall back to a `ZStack` with the active tab on top — every tab's
    /// container stays alive so per-tab scroll position is preserved across
    /// switches, matching the iOS pager's behavior. Feed-switching on macOS
    /// is via the tab strip only.
    @ViewBuilder
    private var pager: some View {
        #if os(iOS)
        TabView(selection: $selectedTabID) {
            ForEach(tabs) { tab in
                feedListContainer(for: tab)
                    .tag(tab.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea(edges: .bottom)
        #else
        ZStack {
            ForEach(tabs) { tab in
                feedListContainer(for: tab)
                    .opacity(tab.id == selectedTabID ? 1 : 0)
                    .allowsHitTesting(tab.id == selectedTabID)
                    .accessibilityHidden(tab.id != selectedTabID)
            }
        }
        #endif
    }

    /// Builds the per-tab container — same loading / error / list states as the
    /// previous single-feed implementation, but lazy-instantiates the
    /// `FeedViewModel` for the tab's `FeedSelection` on first appearance and
    /// keeps it cached across tab switches so scroll position is retained.
    private func feedListContainer(for tab: HomeFeedTab) -> some View {
        let vm = vmCache[tab.selection]
        return Group {
            if let vm {
                if vm.posts.isEmpty && vm.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.posts.isEmpty, let msg = vm.errorMessage {
                    errorView(msg, vm: vm)
                } else if vm.posts.isEmpty {
                    emptyView(for: tab)
                } else {
                    list(vm: vm)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: tab.id) {
            logger.debug("task fired, tab=\(tab.id, privacy: .public)")
            if vmCache[tab.selection] == nil {
                if tab.selection == .timeline {
                    // Use the store created and started in boot() — no loadInitial needed here
                    // because it is already in-flight on a plain Task that SwiftUI cannot cancel.
                    logger.debug("attaching pre-built timeline store from boot()")
                    let viewModel = FeedViewModel(store: bootTimelineStore, selection: .timeline)
                    viewModel.filter = filter
                    vmCache[.timeline] = viewModel
                } else {
                    logger.debug("creating FeedViewModel for tab=\(tab.id, privacy: .public)")
                    let viewModel = FeedViewModel(
                        network: network,
                        accountStore: accountStore,
                        cache: cache,
                        selection: tab.selection
                    )
                    viewModel.filter = filter
                    vmCache[tab.selection] = viewModel
                    await vmCache[tab.selection]?.loadInitial()
                }
            } else {
                logger.debug("reusing existing FeedViewModel for tab=\(tab.id, privacy: .public)")
            }
        }
        .onChange(of: filter) { _, newFilter in
            vmCache[tab.selection]?.filter = newFilter
        }
    }

    /// Render-time fallback name for a pinned feed when we don't have its
    /// resolved `GeneratorView` metadata. Falls back to the rkey portion of
    /// the AT-URI so the strip never shows an empty label, even before the
    /// `My Feeds` screen has resolved metadata.
    private func pinnedFeedDisplayName(_ feed: SavedFeed) -> String {
        feed.value.components(separatedBy: "/").last ?? feed.value
    }

    /// Notification name posted by the iOS custom tab bar when the user taps
    /// the Home tab while already on Home. Defined here as a literal string
    /// because `BlueskyFeed` cannot import the app target where the
    /// canonical name is declared (`PushRouter.swift`). Keep both names in
    /// sync — they are both opaque identifiers, so the strings must match.
    private static let scrollToTopNotification =
        Foundation.Notification.Name("co.sstools.bluesky.scrollFeedToTop")

    /// Stable scroll anchor for the first post in the feed. Used by
    /// `ScrollViewReader.scrollTo` to implement RN's "tap Home to jump to
    /// the top" behavior — the system `TabView`'s implicit scroll-to-top
    /// is unavailable now that iOS uses a custom tab bar.
    private static let scrollToTopAnchor = "feed.top"

    private func list(vm: FeedViewModel) -> some View {
        let displayed = vm.filteredPosts
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Invisible anchor at the top of the list so the
                    // scroll-to-top notification can target a stable id
                    // even when the feed is empty mid-refresh.
                    Color.clear
                        .frame(height: 0)
                        .id(Self.scrollToTopAnchor)
                    ForEach(displayed, id: \.post.uri) { item in
                        PostCard(item: item, actions: actions(for: item, vm: vm))
                            .onAppear {
                                if item.post.uri == vm.posts.last?.post.uri {
                                    Task { await vm.loadMore() }
                                }
                            }
                        Divider()
                    }
                    if vm.isLoading {
                        HStack { Spacer(); ProgressView(); Spacer() }.padding()
                    }
                }
            }
            .refreshable { await vm.refresh() }
            .onReceive(NotificationCenter.default.publisher(for: Self.scrollToTopNotification)) { _ in
                // Only the active tab should respond to a scroll-to-top tap;
                // off-screen tabs in the pager would otherwise all scroll
                // simultaneously which is invisible but wasteful.
                guard tabs.first(where: { $0.id == selectedTabID })?.selection == vm.selection else {
                    return
                }
                withAnimation { proxy.scrollTo(Self.scrollToTopAnchor, anchor: .top) }
            }
        }
    }

    private func errorView(_ message: String, vm: FeedViewModel) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await vm.refresh() } }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyView(for tab: HomeFeedTab) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No posts in \(tab.label) yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func actions(for item: FeedViewPost, vm: FeedViewModel) -> PostCard.Actions {
        var a = PostCard.Actions()
        a.onTap = onPostTap
        a.onAuthorTap = onAuthorTap
        a.onReply = { post in replyTarget = post }
        a.onLike = { post in
            // Use the freshest local snapshot as the basis; the store will
            // re-check the server when its viewer-state cache is stale and
            // pick like vs unlike against the freshly confirmed state. See
            // issue #0041.
            let current = vm.posts.first(where: { $0.post.uri == post.uri })?.post ?? post
            Task { await vm.toggleLike(post: current) }
        }
        a.onRepost = { post in
            let current = vm.posts.first(where: { $0.post.uri == post.uri })?.post ?? post
            // If our local snapshot says the post is already reposted, jump
            // straight to unrepost — the store will still freshen the viewer
            // state internally and skip the network call when it's already
            // in the desired state. Otherwise show the Repost / Quote chooser.
            if current.viewer?.repost != nil {
                Task { await vm.toggleRepost(post: current) }
            } else {
                repostMenuTarget = current
                repostTargetVM = vm
            }
        }
        a.isBookmarked = item.post.viewer?.bookmarked ?? false
        a.onBookmark = { post in Task { await vm.bookmark(post: post) } }
        return a
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

private final class PreviewNoOpCache: CacheStore, @unchecked Sendable {
    nonisolated func store<T: Codable & Sendable>(_ value: T, for key: String, ttl: TimeInterval?) async throws {}
    nonisolated func fetch<T: Codable & Sendable>(_ type: T.Type, for key: String) async throws -> CacheResult<T>? { nil }
    nonisolated func evict(for key: String) async throws {}
    nonisolated func evictAll() async throws {}
}

// MARK: - Previews

#Preview("FeedView — Light") {
    NavigationStack {
        FeedView(
            network: PreviewNoOpNetwork(),
            accountStore: PreviewNoOpAccountStore(),
            cache: PreviewNoOpCache()
        )
    }
    .preferredColorScheme(.light)
}

#Preview("FeedView — Dark") {
    NavigationStack {
        FeedView(
            network: PreviewNoOpNetwork(),
            accountStore: PreviewNoOpAccountStore(),
            cache: PreviewNoOpCache()
        )
    }
    .preferredColorScheme(.dark)
}
