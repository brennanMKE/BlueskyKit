import Foundation

// MARK: - app.bsky.actor.searchActors

public struct SearchActorsResponse: Decodable, Sendable {
    public let actors: [ProfileView]
    public let cursor: String?
}

// MARK: - app.bsky.actor.searchActorsTypeahead

public struct SearchActorsTypeaheadResponse: Decodable, Sendable {
    public let actors: [ProfileBasic]
}

// MARK: - app.bsky.actor.getSuggestions

public struct GetSuggestionsResponse: Decodable, Sendable {
    public let actors: [ProfileView]
    public let cursor: String?
}

// MARK: - app.bsky.feed.searchPosts

public struct SearchPostsResponse: Decodable, Sendable {
    public let posts: [PostView]
    public let cursor: String?
    public let hitsTotal: Int?
}

// MARK: - app.bsky.feed.getSuggestedFeeds

public struct GetSuggestedFeedsResponse: Decodable, Sendable {
    public let feeds: [GeneratorView]
    public let cursor: String?
}

// MARK: - app.bsky.unspecced.getTrendingTopics

public struct TrendingTopic: Codable, Sendable {
    public let topic: String
    public let displayName: String?
    public let description: String?
    public let link: String

    public init(topic: String, displayName: String?, description: String?, link: String) {
        self.topic = topic
        self.displayName = displayName
        self.description = description
        self.link = link
    }
}

public struct GetTrendingTopicsResponse: Codable, Sendable {
    public let topics: [TrendingTopic]

    public init(topics: [TrendingTopic]) {
        self.topics = topics
    }
}
