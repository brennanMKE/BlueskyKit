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

/// The home feed view — feed switcher at top, infinite-scroll post list below.
public struct FeedView: View {

    private let network: any NetworkClient
    private let accountStore: any AccountStore
    private let cache: any CacheStore
    var onPostTap: ((PostView) -> Void)?
    var onAuthorTap: ((ProfileBasic) -> Void)?

    public init(
        network: any NetworkClient,
        accountStore: any AccountStore,
        cache: any CacheStore,
        onPostTap: ((PostView) -> Void)? = nil,
        onAuthorTap: ((ProfileBasic) -> Void)? = nil
    ) {
        self.network = network
        self.accountStore = accountStore
        self.cache = cache
        self.onPostTap = onPostTap
        self.onAuthorTap = onAuthorTap
    }

    @State private var selection: FeedSelection = .timeline
    @State private var viewModels: [FeedSelection: FeedViewModel] = [:]
    @State private var replyTarget: PostView? = nil
    @State private var repostMenuTarget: PostView? = nil
    @State private var repostTargetVM: FeedViewModel? = nil
    @State private var quoteTarget: PostView? = nil

    public var body: some View {
        VStack(spacing: 0) {
            FeedSwitcherView(selection: $selection)
            Divider()
            feedList
        }
        .navigationTitle("Home")
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
            if let vm = viewModels[selection] {
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
            if viewModels[selection] == nil {
                logger.debug("creating FeedViewModel for \(String(describing: selection), privacy: .public)")
                viewModels[selection] = FeedViewModel(
                    network: network,
                    accountStore: accountStore,
                    cache: cache,
                    selection: selection
                )
            } else {
                logger.debug("reusing existing FeedViewModel for \(String(describing: selection), privacy: .public)")
            }
            logger.debug("calling loadInitial")
            await viewModels[selection]?.loadInitial()
            let postCount = viewModels[selection]?.posts.count ?? -1
            let errorMsg = viewModels[selection]?.errorMessage ?? "nil"
            logger.debug("loadInitial returned, posts=\(postCount, privacy: .public), error=\(errorMsg, privacy: .public)")
        }
    }

    private func list(vm: FeedViewModel) -> some View {
        List {
            ForEach(vm.posts, id: \.post.uri) { item in
                PostCard(item: item, actions: actions(for: item, vm: vm))
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .onAppear {
                        if item.post.uri == vm.posts.last?.post.uri {
                            Task { await vm.loadMore() }
                        }
                    }
            }
            if vm.isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
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
            Task {
                if post.viewer?.like != nil {
                    await vm.unlike(post: post)
                } else {
                    await vm.like(post: post)
                }
            }
        }
        a.onRepost = { post in
            if post.viewer?.repost != nil {
                Task { await vm.unrepost(post: post) }
            } else {
                repostMenuTarget = post
                repostTargetVM = vm
            }
        }
        return a
    }
}
