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
