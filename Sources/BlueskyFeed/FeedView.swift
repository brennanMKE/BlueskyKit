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

/// The home feed view — feed switcher at top, infinite-scroll post list below.
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

    @State private var selection: FeedSelection = .timeline
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

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                FeedSwitcherView(selection: $selection)
                Spacer(minLength: 0)
                Menu {
                    Toggle("Hide Replies", isOn: $filter.hideReplies)
                    Toggle("Hide Reposts", isOn: $filter.hideReposts)
                } label: {
                    Image(systemName: filter.isActive
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                        .symbolRenderingMode(.hierarchical)
                        .font(.title3)
                        .frame(width: 32, height: 32)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .padding(.trailing, 12)
                .help("Filter Feed")
            }
            Divider()
            feedList
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

    private var feedList: some View {
        Group {
            if let vm = vmCache[selection] {
                if vm.posts.isEmpty && vm.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.posts.isEmpty, let msg = vm.errorMessage {
                    errorView(msg, vm: vm)
                } else {
                    list(vm: vm)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: selection) {
            logger.debug("task fired, selection=\(String(describing: selection), privacy: .public)")
            if vmCache[selection] == nil {
                if selection == .timeline {
                    // Use the store created and started in boot() — no loadInitial needed here
                    // because it is already in-flight on a plain Task that SwiftUI cannot cancel.
                    logger.debug("attaching pre-built timeline store from boot()")
                    let vm = FeedViewModel(store: bootTimelineStore, selection: .timeline)
                    vm.filter = filter
                    vmCache[.timeline] = vm
                } else {
                    logger.debug("creating FeedViewModel for \(String(describing: selection), privacy: .public)")
                    let vm = FeedViewModel(
                        network: network,
                        accountStore: accountStore,
                        cache: cache,
                        selection: selection
                    )
                    vm.filter = filter
                    vmCache[selection] = vm
                    logger.debug("calling loadInitial")
                    await vmCache[selection]?.loadInitial()
                    let postCount = vmCache[selection]?.posts.count ?? -1
                    let errorMsg = vmCache[selection]?.errorMessage ?? "nil"
                    logger.debug("loadInitial returned, posts=\(postCount, privacy: .public), error=\(errorMsg, privacy: .public)")
                }
            } else {
                logger.debug("reusing existing FeedViewModel for \(String(describing: selection), privacy: .public)")
            }
        }
        .onChange(of: filter) { _, newFilter in
            vmCache[selection]?.filter = newFilter
        }
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
