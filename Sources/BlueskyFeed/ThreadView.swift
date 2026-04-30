import SwiftUI
import BlueskyCore
import BlueskyKit
import BlueskyUI
import BlueskyComposer

/// Renders a post thread — root post with its parent chain above and reply tree below.
public struct ThreadView: View {

    private let uri: ATURI
    private let network: any NetworkClient
    private let accountStore: any AccountStore

    @State private var viewModel: ThreadViewModel
    @State private var replyTarget: PostView? = nil

    public init(uri: ATURI, network: any NetworkClient, accountStore: any AccountStore) {
        self.uri = uri
        self.network = network
        self.accountStore = accountStore
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
                ScrollView {
                    LazyVStack(spacing: 0) {
                        threadNodes(thread)
                    }
                }
            }
        }
        .navigationTitle("Thread")
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

    // MARK: - Recursive tree renderer
    // Returns AnyView to break the self-referential `some View` compile error on recursive branches.

    private func threadNodes(_ node: ThreadViewPost) -> AnyView {
        switch node {
        case .post(let tp):
            return AnyView(postNode(tp))
        case .notFound:
            return AnyView(unavailablePlaceholder("Post not found"))
        case .blocked:
            return AnyView(unavailablePlaceholder("Blocked post"))
        case .unknown:
            return AnyView(EmptyView())
        }
    }

    private func postNode(_ tp: ThreadPost) -> some View {
        VStack(spacing: 0) {
            // Parent chain
            if let parent = tp.parent {
                threadNodes(parent)
                replyConnector
            }
            // This post
            PostCard(
                item: FeedViewPost(post: tp.post, reply: nil, reason: nil),
                actions: postCardActions(for: tp.post)
            )
            Divider()
            // Replies
            if let replies = tp.replies {
                ForEach(replies, id: \.stableID) { reply in
                    HStack(alignment: .top, spacing: 0) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(width: 2)
                            .padding(.leading, 30)
                        threadNodes(reply)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func postCardActions(for post: PostView) -> PostCard.Actions {
        var a = PostCard.Actions()
        a.onReply = { post in replyTarget = post }
        return a
    }

    // MARK: - Supporting views

    private var replyConnector: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.3))
            .frame(width: 2, height: 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 30)
    }

    private func unavailablePlaceholder(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
    }

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

// MARK: - Stable ID helper

private extension ThreadViewPost {
    var stableID: String {
        switch self {
        case .post(let tp):        return tp.post.uri.rawValue
        case .notFound(let uri):   return "notfound:\(uri.rawValue)"
        case .blocked(let uri):    return "blocked:\(uri.rawValue)"
        case .unknown(let t):      return "unknown:\(t)"
        }
    }
}
