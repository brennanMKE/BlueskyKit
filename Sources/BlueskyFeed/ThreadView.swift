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
    private let onAuthorTap: ((ProfileBasic) -> Void)?

    @State private var viewModel: ThreadViewModel
    @State private var replyTarget: PostView? = nil

    public init(
        uri: ATURI,
        network: any NetworkClient,
        accountStore: any AccountStore,
        onAuthorTap: ((ProfileBasic) -> Void)? = nil
    ) {
        self.uri = uri
        self.network = network
        self.accountStore = accountStore
        self.onAuthorTap = onAuthorTap
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

    // MARK: - Flat list

    private func threadList(_ node: ThreadViewPost) -> some View {
        let rows = flattenThread(node)
        return List {
            ForEach(rows, id: \.post.uri) { item in
                PostCard(item: item, actions: actions(for: item.post))
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .refreshable { await viewModel.load() }
    }

    /// Walk the thread tree: ancestors (oldest first) → focal post → direct replies.
    private func flattenThread(_ node: ThreadViewPost) -> [FeedViewPost] {
        guard case .post(let tp) = node else { return [] }

        var result: [FeedViewPost] = []

        // Ancestors (parent chain, oldest first)
        let ancestors = collectAncestors(tp.parent)
        result.append(contentsOf: ancestors)

        // Focal post
        result.append(FeedViewPost(post: tp.post, reply: nil, reason: nil))

        // Direct replies (flat — one level only)
        if let replies = tp.replies {
            for reply in replies {
                if case .post(let rtp) = reply {
                    result.append(FeedViewPost(post: rtp.post, reply: nil, reason: nil))
                }
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

    private func actions(for post: PostView) -> PostCard.Actions {
        var a = PostCard.Actions()
        a.onReply = { p in replyTarget = p }
        a.onAuthorTap = onAuthorTap
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
