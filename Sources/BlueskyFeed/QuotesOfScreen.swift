import SwiftUI
import Observation
import BlueskyCore
import BlueskyKit
import BlueskyUI
import os

/// Paginated feed of posts that quote a given post — destination of the
/// "X quotes" tap target on a focal post (#0139). Mirrors RN's
/// `PostQuotesScreen` (`Bluesky-ReactNative/src/screens/Post/PostQuotes.tsx`)
/// which pages over `app.bsky.feed.getQuotes` and filters out detached
/// embed views (RN's `select` step in `usePostQuotesQuery`).
public struct QuotesOfScreen: View {

    private let postURI: ATURI
    private let network: any NetworkClient
    private let onPostTap: ((PostView) -> Void)?
    private let onAuthorTap: ((ProfileBasic) -> Void)?

    @State private var viewModel: QuotesViewModel

    public init(
        postURI: ATURI,
        network: any NetworkClient,
        onPostTap: ((PostView) -> Void)? = nil,
        onAuthorTap: ((ProfileBasic) -> Void)? = nil
    ) {
        self.postURI = postURI
        self.network = network
        self.onPostTap = onPostTap
        self.onAuthorTap = onAuthorTap
        _viewModel = State(wrappedValue: QuotesViewModel(network: network, postURI: postURI))
    }

    public var body: some View {
        Group {
            if viewModel.posts.isEmpty && !viewModel.isLoading && viewModel.errorMessage == nil {
                ContentUnavailableView(
                    "No Quotes Yet",
                    systemImage: "quote.bubble",
                    description: Text("When people quote this post, they'll show up here.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.posts, id: \.uri) { post in
                            PostCard(
                                item: FeedViewPost(post: post, reply: nil, reason: nil),
                                actions: actions()
                            )
                            .onAppear {
                                if post.uri == viewModel.posts.last?.uri {
                                    Task { await viewModel.loadMore() }
                                }
                            }
                            Divider()
                        }
                    }
                }
                .refreshable { await viewModel.load() }
            }
        }
        .navigationTitle("Quotes")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await viewModel.loadIfNeeded() }
        .overlay {
            if viewModel.isLoading && viewModel.posts.isEmpty {
                ProgressView()
            }
        }
    }

    private func actions() -> PostCard.Actions {
        var a = PostCard.Actions()
        a.onTap = { onPostTap?($0) }
        a.onAuthorTap = onAuthorTap
        return a
    }
}

// MARK: - QuotesViewModel

@Observable @MainActor
public final class QuotesViewModel {
    public private(set) var posts: [PostView] = []
    public private(set) var cursor: Cursor?
    public private(set) var hasMore: Bool = true
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?

    private let network: any NetworkClient
    private let postURI: ATURI
    private let pageSize = 30
    private let logger = Logger(subsystem: "app.bsky", category: "QuotesViewModel")

    public init(network: any NetworkClient, postURI: ATURI) {
        self.network = network
        self.postURI = postURI
    }

    public func loadIfNeeded() async {
        guard posts.isEmpty, !isLoading else { return }
        await load()
    }

    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let resp: GetQuotesResponse = try await network.get(
                lexicon: "app.bsky.feed.getQuotes",
                params: [
                    "uri": postURI.rawValue,
                    "limit": String(pageSize)
                ]
            )
            posts = filterDetached(resp.posts)
            cursor = resp.cursor
            hasMore = resp.cursor != nil
        } catch {
            logger.error("getQuotes load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func loadMore() async {
        guard hasMore, !isLoading, let cursor else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let resp: GetQuotesResponse = try await network.get(
                lexicon: "app.bsky.feed.getQuotes",
                params: [
                    "uri": postURI.rawValue,
                    "limit": String(pageSize),
                    "cursor": cursor
                ]
            )
            posts.append(contentsOf: filterDetached(resp.posts))
            self.cursor = resp.cursor
            hasMore = resp.cursor != nil
        } catch {
            logger.error("getQuotes loadMore failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    /// Strip posts whose embedded record is a detached view. RN's
    /// `usePostQuotesQuery` does the same in its `select` step — once the
    /// quoted post is detached (`app.bsky.embed.record#viewDetached`) the
    /// row has nothing meaningful to show. Our `EmbedRecordContent` decoder
    /// surfaces unknown record types as `.unknown(typeString)`, so the
    /// detached variant lands in that case.
    private func filterDetached(_ posts: [PostView]) -> [PostView] {
        posts.filter { post in
            guard case .record(let recordEmbed) = post.embed else { return true }
            if case .unknown(let type) = recordEmbed.record,
               type == "app.bsky.embed.record#viewDetached" {
                return false
            }
            return true
        }
    }
}

// MARK: - Preview helpers

private final class PreviewNoOpNetwork: NetworkClient, @unchecked Sendable {
    nonisolated func get<R: Decodable & Sendable>(lexicon: String, params: [String: String]) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func post<B: Encodable & Sendable, R: Decodable & Sendable>(lexicon: String, body: B) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func upload<R: Decodable & Sendable>(lexicon: String, data: Data, mimeType: String) async throws -> R { throw ATError.unknown("preview") }
}

// MARK: - Previews

#Preview("QuotesOfScreen — Light") {
    NavigationStack {
        QuotesOfScreen(
            postURI: ATURI(rawValue: "at://did:plc:alice/app.bsky.feed.post/abc"),
            network: PreviewNoOpNetwork()
        )
    }
    .blueskyTheme(.light)
    .preferredColorScheme(.light)
}

#Preview("QuotesOfScreen — Dark") {
    NavigationStack {
        QuotesOfScreen(
            postURI: ATURI(rawValue: "at://did:plc:alice/app.bsky.feed.post/abc"),
            network: PreviewNoOpNetwork()
        )
    }
    .blueskyTheme(.dark)
    .preferredColorScheme(.dark)
}
