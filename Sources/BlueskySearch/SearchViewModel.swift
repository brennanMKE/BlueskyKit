import Foundation
import Observation
import BlueskyCore
import BlueskyKit

@Observable
public final class SearchViewModel {

    public enum SearchTab: String, CaseIterable, Identifiable {
        case people, posts, feeds
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .people: "People"
            case .posts:  "Posts"
            case .feeds:  "Feeds"
            }
        }
    }

    public var query: String = ""
    public var activeTab: SearchTab = .people

    public var actors: [ProfileView] = []
    public var posts: [PostView] = []
    public var suggestedFeeds: [GeneratorView] = []

    public var actorsCursor: String?
    public var postsCursor: String?

    public var suggestedActors: [ProfileView] = []

    public var isLoading = false
    public var errorMessage: String?

    private let network: any NetworkClient
    private var debounceTask: Task<Void, Never>?

    public init(network: any NetworkClient) {
        self.network = network
    }

    // MARK: - Debounced search trigger

    public func onQueryChange() {
        debounceTask?.cancel()
        let q = query
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            guard !Task.isCancelled, !q.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            await search(fresh: true)
        }
    }

    // MARK: - Search

    public func search(fresh: Bool) async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        guard !isLoading else { return }
        if fresh {
            actors = []
            posts = []
            suggestedFeeds = []
            actorsCursor = nil
            postsCursor = nil
        }
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            switch activeTab {
            case .people:
                var params: [String: String] = ["q": q, "limit": "25"]
                if !fresh, let c = actorsCursor { params["cursor"] = c }
                let resp: SearchActorsResponse = try await network.get(
                    lexicon: "app.bsky.actor.searchActors", params: params
                )
                if fresh { actors = resp.actors } else { actors.append(contentsOf: resp.actors) }
                actorsCursor = resp.cursor
            case .posts:
                var params: [String: String] = ["q": q, "limit": "25"]
                if !fresh, let c = postsCursor { params["cursor"] = c }
                let resp: SearchPostsResponse = try await network.get(
                    lexicon: "app.bsky.feed.searchPosts", params: params
                )
                if fresh { posts = resp.posts } else { posts.append(contentsOf: resp.posts) }
                postsCursor = resp.cursor
            case .feeds:
                let params: [String: String] = ["q": q, "limit": "25"]
                let resp: GetSuggestedFeedsResponse = try await network.get(
                    lexicon: "app.bsky.feed.getSuggestedFeeds", params: params
                )
                suggestedFeeds = resp.feeds
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func loadMore() async {
        await search(fresh: false)
    }

    // MARK: - Suggestions (shown when query is empty)

    public func loadSuggestions() async {
        guard suggestedActors.isEmpty else { return }
        do {
            let resp: GetSuggestionsResponse = try await network.get(
                lexicon: "app.bsky.actor.getSuggestions", params: ["limit": "20"]
            )
            suggestedActors = resp.actors
        } catch {}
    }
}
