import Foundation

// MARK: - app.bsky.graph.defs#starterPackView

/// Full view of a starter pack returned by `app.bsky.graph.getStarterPack`.
public struct StarterPackView: Decodable, Sendable {
    public let uri: ATURI
    public let cid: CID
    public let creator: ProfileBasic
    public let list: ListBasic?
    public let listItemsSample: [ListItemView]?
    public let feeds: [GeneratorView]?
    public let joinedWeekCount: Int?
    public let joinedAllTimeCount: Int?
    public let labels: [Label]
    public let indexedAt: Date

    public init(
        uri: ATURI,
        cid: CID,
        creator: ProfileBasic,
        list: ListBasic? = nil,
        listItemsSample: [ListItemView]? = nil,
        feeds: [GeneratorView]? = nil,
        joinedWeekCount: Int? = nil,
        joinedAllTimeCount: Int? = nil,
        labels: [Label] = [],
        indexedAt: Date
    ) {
        self.uri = uri
        self.cid = cid
        self.creator = creator
        self.list = list
        self.listItemsSample = listItemsSample
        self.feeds = feeds
        self.joinedWeekCount = joinedWeekCount
        self.joinedAllTimeCount = joinedAllTimeCount
        self.labels = labels
        self.indexedAt = indexedAt
    }
}

// MARK: - app.bsky.graph.defs#starterPackViewBasic

/// Lightweight starter pack reference used in actor-level listings.
public struct StarterPackBasic: Decodable, Sendable {
    public let uri: ATURI
    public let cid: CID
    public let name: String
    public let creator: ProfileBasic
    public let listItemCount: Int?
    public let joinedWeekCount: Int?
    public let joinedAllTimeCount: Int?

    public init(
        uri: ATURI,
        cid: CID,
        name: String,
        creator: ProfileBasic,
        listItemCount: Int? = nil,
        joinedWeekCount: Int? = nil,
        joinedAllTimeCount: Int? = nil
    ) {
        self.uri = uri
        self.cid = cid
        self.name = name
        self.creator = creator
        self.listItemCount = listItemCount
        self.joinedWeekCount = joinedWeekCount
        self.joinedAllTimeCount = joinedAllTimeCount
    }
}

// MARK: - Starter pack record (app.bsky.graph.starterpack)

/// A starter pack record for use with `com.atproto.repo.createRecord`.
public struct StarterPackRecord: Encodable, Sendable {
    private let type: String = "app.bsky.graph.starterpack"
    public let name: String
    public let description: String?
    /// AT-URI of the list backing this starter pack.
    public let list: String
    public let createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case type = "$type", name, description, list, createdAt
    }

    public init(name: String, description: String? = nil, list: ATURI, createdAt: Date = .now) {
        self.name = name
        self.description = description
        self.list = list.rawValue
        self.createdAt = createdAt
    }
}

// MARK: - Response types

public struct GetStarterPackResponse: Decodable, Sendable {
    public let starterPack: StarterPackView
}

public struct GetActorStarterPacksResponse: Decodable, Sendable {
    public let starterPacks: [StarterPackView]
    public let cursor: String?
}
