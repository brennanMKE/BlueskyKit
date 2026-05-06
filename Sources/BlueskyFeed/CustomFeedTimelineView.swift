import SwiftUI
import BlueskyCore
import BlueskyKit
import BlueskyUI
import BlueskyComposer

// MARK: - CustomFeedTimelineView

/// A standalone feed timeline view bound to a single custom-feed AT-URI.
///
/// Used by the My Feeds screen (#0073) to drill into a specific saved or
/// suggested feed. Unlike `FeedView` — which always shows the top-level
/// Following / Discover switcher — this view is parameterised by a single
/// `FeedSelection` and renders that one timeline only. It reuses
/// `FeedStore` and `FeedViewModel` so all the like/repost/bookmark behavior
/// stays consistent with the rest of the app.
public struct CustomFeedTimelineView: View {

    private let network: any NetworkClient
    private let accountStore: any AccountStore
    private let cache: any CacheStore
    private let selection: FeedSelection
    private let title: String
    private let onPostTap: ((PostView) -> Void)?
    private let onAuthorTap: ((ProfileBasic) -> Void)?

    @State private var viewModel: FeedViewModel?
    @State private var replyTarget: PostView? = nil
    @State private var quoteTarget: PostView? = nil
    @State private var repostMenuTarget: PostView? = nil

    @Environment(\.blueskyTheme) private var theme

    public init(
        feedURI: ATURI,
        title: String,
        network: any NetworkClient,
        accountStore: any AccountStore,
        cache: any CacheStore,
        onPostTap: ((PostView) -> Void)? = nil,
        onAuthorTap: ((ProfileBasic) -> Void)? = nil
    ) {
        self.network = network
        self.accountStore = accountStore
        self.cache = cache
        self.selection = .feed(uri: feedURI.rawValue)
        self.title = title
        self.onPostTap = onPostTap
        self.onAuthorTap = onAuthorTap
    }

    public var body: some View {
        Group {
            if let vm = viewModel {
                content(vm: vm)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(theme.colors.background.ignoresSafeArea())
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            if viewModel == nil {
                let vm = FeedViewModel(
                    network: network,
                    accountStore: accountStore,
                    cache: cache,
                    selection: selection
                )
                viewModel = vm
                await vm.loadInitial()
            }
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
            set: { if !$0 { repostMenuTarget = nil } }
        ), titleVisibility: .hidden) {
            Button("Repost") {
                guard let post = repostMenuTarget, let vm = viewModel else { return }
                repostMenuTarget = nil
                Task { await vm.repost(post: post) }
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

    @ViewBuilder
    private func content(vm: FeedViewModel) -> some View {
        if vm.posts.isEmpty && vm.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.posts.isEmpty, let msg = vm.errorMessage {
            errorView(msg, vm: vm)
        } else {
            list(vm: vm)
        }
    }

    private func list(vm: FeedViewModel) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(vm.posts, id: \.post.uri) { item in
                    PostCard(item: item, actions: actions(for: item, vm: vm))
                        .onAppear {
                            if item.post.uri == vm.posts.last?.post.uri {
                                Task { await vm.loadMore() }
                            }
                        }
                    Divider()
                }
                if vm.isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .padding()
                }
            }
        }
        .refreshable { await vm.refresh() }
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
            let current = vm.posts.first(where: { $0.post.uri == post.uri })?.post ?? post
            Task { await vm.toggleLike(post: current) }
        }
        a.onRepost = { post in
            let current = vm.posts.first(where: { $0.post.uri == post.uri })?.post ?? post
            if current.viewer?.repost != nil {
                Task { await vm.toggleRepost(post: current) }
            } else {
                repostMenuTarget = current
            }
        }
        a.isBookmarked = item.post.viewer?.bookmarked ?? false
        a.onBookmark = { post in Task { await vm.bookmark(post: post) } }
        return a
    }
}
