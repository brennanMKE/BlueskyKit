import SwiftUI
import BlueskyCore
import BlueskyKit
import BlueskyUI
import BlueskyComposer

/// Renders a post thread — focal post at the top, direct replies below as a flat list.
public struct ThreadView: View {

    private let uri: ATURI
    private let network: any NetworkClient
    private let accountStore: any AccountStore
    private let bookmarks: (any BookmarkStoring)?
    private let onAuthorTap: ((ProfileBasic) -> Void)?
    private let onPostTap: ((PostView) -> Void)?
    /// Tap on the focal post's "X likes" stat — parent pushes `LikedByScreen`.
    /// Wired through callbacks (rather than internal `navigationDestination`)
    /// so the destination screens can be hosted next to existing destinations
    /// in `MainTabView` without `BlueskyFeed` taking a dependency on them.
    /// The actual stat-row UI that fires these is the responsibility of #0146.
    private let onLikedByTap: ((ATURI) -> Void)?
    private let onRepostedByTap: ((ATURI) -> Void)?
    private let onQuotesTap: ((ATURI) -> Void)?

    @State private var viewModel: ThreadViewModel
    @State private var replyTarget: PostView? = nil
    /// URI of a non-focal post (ancestor or reply) tapped by the user; drives in-thread navigation.
    @State private var selectedReplyURI: ATURI? = nil

    public init(
        uri: ATURI,
        network: any NetworkClient,
        accountStore: any AccountStore,
        bookmarks: (any BookmarkStoring)? = nil,
        onAuthorTap: ((ProfileBasic) -> Void)? = nil,
        onPostTap: ((PostView) -> Void)? = nil,
        onLikedByTap: ((ATURI) -> Void)? = nil,
        onRepostedByTap: ((ATURI) -> Void)? = nil,
        onQuotesTap: ((ATURI) -> Void)? = nil
    ) {
        self.uri = uri
        self.network = network
        self.accountStore = accountStore
        self.bookmarks = bookmarks
        self.onAuthorTap = onAuthorTap
        self.onPostTap = onPostTap
        self.onLikedByTap = onLikedByTap
        self.onRepostedByTap = onRepostedByTap
        self.onQuotesTap = onQuotesTap
        _viewModel = State(wrappedValue: ThreadViewModel(network: network, uri: uri))
    }

    public var body: some View {
        Group {
            if viewModel.isLoading && viewModel.thread == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let msg = viewModel.errorMessage, viewModel.thread == nil {
                errorView(msg)
            } else if let thread = viewModel.thread {
                threadList(thread)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Thread")
        .adaptiveBlueskyTheme()
        .toolbar { sortToolbar }
        .task { await viewModel.load() }
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
    }

    // MARK: - Toolbar

    /// Reply-sort dropdown. Mirrors RN's `HeaderDropdown`
    /// (`Bluesky-ReactNative/src/screens/PostThread/components/HeaderDropdown.tsx`).
    /// Options span the full lexicon set (`hotness`, `most-likes`,
    /// `newest`, `oldest`, `random`) per the issue spec, even though
    /// the live RN screen surfaces only a subset.
    @ToolbarContentBuilder
    private var sortToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker("Reply sorting", selection: sortBinding) {
                    ForEach(ThreadSort.displayOrder, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Reply sorting", systemImage: "slider.horizontal.3")
            }
            .help("Reply sorting")
            .disabled(viewModel.thread == nil)
        }
    }

    private var sortBinding: Binding<ThreadSort> {
        Binding(
            get: { viewModel.sort },
            set: { viewModel.setSort($0) }
        )
    }

    // MARK: - Flat list

    private func threadList(_ node: ThreadViewPost) -> some View {
        let rows = flattenThread(node)
        let focalURI = focalPostURI(node)
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(rows, id: \.post.uri) { item in
                    PostCard(item: item, actions: actions(for: item.post, focalURI: focalURI))
                    Divider()
                }
            }
        }
        .refreshable { await viewModel.load() }
        .navigationDestination(item: $selectedReplyURI) { uri in
            ThreadView(
                uri: uri,
                network: network,
                accountStore: accountStore,
                bookmarks: bookmarks,
                onAuthorTap: onAuthorTap,
                onPostTap: onPostTap,
                onLikedByTap: onLikedByTap,
                onRepostedByTap: onRepostedByTap,
                onQuotesTap: onQuotesTap
            )
        }
    }

    /// Extract the focal (root) post URI from the loaded thread node.
    private func focalPostURI(_ node: ThreadViewPost) -> ATURI? {
        guard case .post(let tp) = node else { return nil }
        return tp.post.uri
    }

    /// Walk the thread tree: ancestors (oldest first) → focal post → direct replies.
    /// Replies use `viewModel.sortedReplies` so the toolbar Menu's
    /// reply-sort selection drives row order without a refetch.
    private func flattenThread(_ node: ThreadViewPost) -> [FeedViewPost] {
        guard case .post(let tp) = node else { return [] }

        var result: [FeedViewPost] = []

        // Ancestors (parent chain, oldest first)
        let ancestors = collectAncestors(tp.parent)
        result.append(contentsOf: ancestors)

        // Focal post
        result.append(FeedViewPost(post: tp.post, reply: nil, reason: nil))

        // Direct replies (flat — one level only), client-sorted per
        // the active `ThreadSort` selection.
        for reply in viewModel.sortedReplies {
            if case .post(let rtp) = reply {
                result.append(FeedViewPost(post: rtp.post, reply: nil, reason: nil))
            }
        }

        return result
    }

    /// Recursively collect the parent chain, returning oldest-first.
    private func collectAncestors(_ node: ThreadViewPost?) -> [FeedViewPost] {
        guard let node, case .post(let tp) = node else { return [] }
        var chain = collectAncestors(tp.parent)
        chain.append(FeedViewPost(post: tp.post, reply: nil, reason: nil))
        return chain
    }

    // MARK: - Actions

    private func actions(for post: PostView, focalURI: ATURI?) -> PostCard.Actions {
        var a = PostCard.Actions()
        // Tapping a non-focal row (ancestor or reply) pushes a new ThreadView for that
        // post. The focal post is already on screen, so a tap there is a no-op. Pushing
        // via a self-owned navigationDestination avoids the "same item rebound" pitfall
        // that prevented navigation when the parent's binding was re-set to the
        // currently-displayed URI.
        a.onTap = { tapped in
            if tapped.uri == focalURI {
                return
            }
            selectedReplyURI = tapped.uri
        }
        a.onReply = { p in replyTarget = p }
        a.onAuthorTap = onAuthorTap
        a.isBookmarked = bookmarks?.isBookmarked(uri: post.uri.rawValue) ?? false
        a.onBookmark = { p in bookmarks?.toggle(post: p) }
        return a
    }

    // MARK: - Error view

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await viewModel.load() } }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

#Preview("ThreadView — Light") {
    NavigationStack {
        ThreadView(
            uri: ATURI(rawValue: "at://did:plc:alice/app.bsky.feed.post/abc"),
            network: PreviewNoOpNetwork(),
            accountStore: PreviewNoOpAccountStore()
        )
    }
    .preferredColorScheme(.light)
}

#Preview("ThreadView — Dark") {
    NavigationStack {
        ThreadView(
            uri: ATURI(rawValue: "at://did:plc:alice/app.bsky.feed.post/abc"),
            network: PreviewNoOpNetwork(),
            accountStore: PreviewNoOpAccountStore()
        )
    }
    .preferredColorScheme(.dark)
}
