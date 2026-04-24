import Foundation

// MARK: - app.bsky.feed.defs#generatorView

/// A feed generator ("custom feed") as returned by the API.
public struct GeneratorView: Codable, Sendable {
    public let uri: ATURI
    public let cid: CID
    /// The DID of the feed generator service (lexicon service PDS).
    public let did: DID
    public let creator: ProfileView
    public let displayName: String
    public let description: String?
    public let descriptionFacets: [RichTextFacet]?
    public let avatar: URL?
    public let likeCount: Int?
    public let acceptsInteractions: Bool?
    public let labels: [Label]
    public let viewer: GeneratorViewerState?
    public let indexedAt: Date

    public init(
        uri: ATURI,
        cid: CID,
        did: DID,
        creator: ProfileView,
        displayName: String,
        description: String? = nil,
        descriptionFacets: [RichTextFacet]? = nil,
        avatar: URL? = nil,
        likeCount: Int? = nil,
        acceptsInteractions: Bool? = nil,
        labels: [Label] = [],
        viewer: GeneratorViewerState? = nil,
        indexedAt: Date = .now
    ) {
        self.uri = uri
        self.cid = cid
        self.did = did
        self.creator = creator
        self.displayName = displayName
        self.description = description
        self.descriptionFacets = descriptionFacets
        self.avatar = avatar
        self.likeCount = likeCount
        self.acceptsInteractions = acceptsInteractions
        self.labels = labels
        self.viewer = viewer
        self.indexedAt = indexedAt
    }
}

/// The authenticated viewer's relationship to a feed generator.
public struct GeneratorViewerState: Codable, Sendable {
    /// AT-URI of the viewer's like record, if liked.
    public let like: ATURI?

    public init(like: ATURI?) {
        self.like = like
    }
}

// MARK: - Response types

public struct GetFeedGeneratorsResponse: Codable, Sendable {
    public let feeds: [GeneratorView]

    public init(feeds: [GeneratorView]) {
        self.feeds = feeds
    }
}

public struct GetActorFeedsResponse: Codable, Sendable {
    public let feeds: [GeneratorView]
    public let cursor: Cursor?

    public init(feeds: [GeneratorView], cursor: Cursor?) {
        self.feeds = feeds
        self.cursor = cursor
    }
}
