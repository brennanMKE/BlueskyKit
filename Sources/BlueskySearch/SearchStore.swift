import Foundation
import OSLog
import Observation
import BlueskyCore
import BlueskyKit

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "co.sstools.Bluesky", category: "SearchStore")

// MARK: - SearchTab

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

// MARK: - SearchStoring

public protocol SearchStoring: AnyObject, Observable, Sendable {
    var actors: [ProfileView] { get }
    var posts: [PostView] { get }
    var suggestedFeeds: [GeneratorView] { get }
    var suggestedActors: [ProfileView] { get }
    var trendingTopics: [TrendingTopic] { get }
    var actorsCursor: String? { get }
    var postsCursor: String? { get }
    var isLoading: Bool { get }
    var errorMessage: String? { get }

    func search(query: String, tab: SearchTab, fresh: Bool) async
    func loadSuggestions() async
    func loadTrending() async
    func clearResults()
}

// MARK: - SearchStore

@Observable
public final class SearchStore: SearchStoring {

    public private(set) var actors: [ProfileView] = []
    public private(set) var posts: [PostView] = []
    public private(set) var suggestedFeeds: [GeneratorView] = []
    public private(set) var suggestedActors: [ProfileView] = []
    public private(set) var trendingTopics: [TrendingTopic] = []
    public private(set) var actorsCursor: String?
    public private(set) var postsCursor: String?
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    private let network: any NetworkClient

    public init(network: any NetworkClient) {
        self.network = network
    }

    // MARK: - Search

    public func search(query: String, tab: SearchTab, fresh: Bool) async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, !isLoading else { return }
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
            switch tab {
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
            logger.error("search error: \(error, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func clearResults() {
        actors = []
        posts = []
        suggestedFeeds = []
        actorsCursor = nil
        postsCursor = nil
    }

    // MARK: - Suggestions

    public func loadSuggestions() async {
        guard suggestedActors.isEmpty else { return }
        do {
            let resp: GetSuggestionsResponse = try await network.get(
                lexicon: "app.bsky.actor.getSuggestions", params: ["limit": "20"]
            )
            suggestedActors = resp.actors
        } catch {}
    }

    public func loadTrending() async {
        do {
            let resp: GetTrendingTopicsResponse = try await network.get(
                lexicon: "app.bsky.unspecced.getTrendingTopics", params: ["limit": "10"]
            )
            trendingTopics = resp.topics
        } catch {
            logger.info("Trending topics unavailable: \(error, privacy: .public)")
            // trendingTopics stays empty if the endpoint is unavailable
        }
    }
}
