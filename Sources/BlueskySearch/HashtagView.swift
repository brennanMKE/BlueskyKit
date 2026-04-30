import SwiftUI
import BlueskyCore
import BlueskyKit
import BlueskyUI

private final class PreviewNoOpNetwork: NetworkClient, @unchecked Sendable {
    nonisolated func get<R: Decodable & Sendable>(lexicon: String, params: [String: String]) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func post<B: Encodable & Sendable, R: Decodable & Sendable>(lexicon: String, body: B) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func upload<R: Decodable & Sendable>(lexicon: String, data: Data, mimeType: String) async throws -> R { throw ATError.unknown("preview") }
}

/// Displays a feed of posts for a given hashtag, loaded via `app.bsky.feed.searchPosts`.
public struct HashtagView: View {
    private let hashtag: String   // without the # prefix
    private let network: any NetworkClient

    @State private var posts: [FeedViewPost] = []
    @State private var cursor: String?
    @State private var isLoading = false
    @State private var errorMessage: String?

    public init(hashtag: String, network: any NetworkClient) {
        self.hashtag = hashtag
        self.network = network
    }

    public var body: some View {
        Group {
            if isLoading && posts.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let msg = errorMessage, posts.isEmpty {
                Text(msg).foregroundStyle(.secondary).padding()
            } else {
                List {
                    ForEach(posts, id: \.post.uri) { item in
                        PostCard(item: item)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .onAppear {
                                if item.post.uri == posts.last?.post.uri {
                                    Task { await loadMore() }
                                }
                            }
                    }
                    if isLoading {
                        HStack { Spacer(); ProgressView(); Spacer() }
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .refreshable { await load(reset: true) }
            }
        }
        .navigationTitle("#\(hashtag)")
        .task { await load(reset: true) }
        .adaptiveBlueskyTheme()
    }

    // MARK: - Data loading

    private func load(reset: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        if reset { cursor = nil; posts = [] }
        errorMessage = nil
        do {
            var params: [String: String] = ["q": "#\(hashtag)", "limit": "50"]
            if let cursor { params["cursor"] = cursor }
            let response: SearchPostsResponse = try await network.get(
                lexicon: "app.bsky.feed.searchPosts", params: params
            )
            cursor = response.cursor
            let feedItems = response.posts.map { FeedViewPost(post: $0, reply: nil, reason: nil) }
            if reset {
                posts = feedItems
            } else {
                posts.append(contentsOf: feedItems)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard cursor != nil else { return }
        await load(reset: false)
    }
}

// MARK: - Previews

#Preview("HashtagView — Light") {
    NavigationStack {
        HashtagView(hashtag: "bluesky", network: PreviewNoOpNetwork())
    }
    .preferredColorScheme(.light)
}

#Preview("HashtagView — Dark") {
    NavigationStack {
        HashtagView(hashtag: "bluesky", network: PreviewNoOpNetwork())
    }
    .preferredColorScheme(.dark)
}
