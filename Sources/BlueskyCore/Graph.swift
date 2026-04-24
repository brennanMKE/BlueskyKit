import Foundation

// MARK: - Follow record (app.bsky.graph.follow)

public struct FollowRecord: Encodable, Sendable {
    private let type: String = "app.bsky.graph.follow"
    public let subject: String
    public let createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case type = "$type", subject, createdAt
    }

    public init(subject: DID, createdAt: Date = .now) {
        self.subject = subject.rawValue
        self.createdAt = createdAt
    }
}

// MARK: - Block record (app.bsky.graph.block)

public struct BlockRecord: Encodable, Sendable {
    private let type: String = "app.bsky.graph.block"
    public let subject: String
    public let createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case type = "$type", subject, createdAt
    }

    public init(subject: DID, createdAt: Date = .now) {
        self.subject = subject.rawValue
        self.createdAt = createdAt
    }
}

// MARK: - Mute / unmute (app.bsky.graph.muteActor / unmuteActor)

public struct MuteActorRequest: Encodable, Sendable {
    public let actor: String

    public init(actor: DID) { self.actor = actor.rawValue }
}

// MARK: - app.bsky.graph.getFollowers / getFollows

public struct GetFollowersResponse: Codable, Sendable {
    public let subject: ProfileView
    public let followers: [ProfileView]
    public let cursor: Cursor?

    public init(subject: ProfileView, followers: [ProfileView], cursor: Cursor?) {
        self.subject = subject
        self.followers = followers
        self.cursor = cursor
    }
}

public struct GetFollowsResponse: Codable, Sendable {
    public let subject: ProfileView
    public let follows: [ProfileView]
    public let cursor: Cursor?

    public init(subject: ProfileView, follows: [ProfileView], cursor: Cursor?) {
        self.subject = subject
        self.follows = follows
        self.cursor = cursor
    }
}

// MARK: - app.bsky.graph.getMutes / getBlocks

public struct GetMutesResponse: Codable, Sendable {
    public let mutes: [ProfileView]
    public let cursor: Cursor?

    public init(mutes: [ProfileView], cursor: Cursor?) {
        self.mutes = mutes
        self.cursor = cursor
    }
}

public struct GetBlocksResponse: Codable, Sendable {
    public let blocks: [ProfileView]
    public let cursor: Cursor?

    public init(blocks: [ProfileView], cursor: Cursor?) {
        self.blocks = blocks
        self.cursor = cursor
    }
}

// MARK: - app.bsky.graph.getLists

public struct GetListsResponse: Codable, Sendable {
    public let lists: [ListView]
    public let cursor: Cursor?

    public init(lists: [ListView], cursor: Cursor?) {
        self.lists = lists
        self.cursor = cursor
    }
}

/// An `app.bsky.graph.defs#listView` — a user-created list (moderation or curation).
public struct ListView: Codable, Sendable {
    public let uri: ATURI
    public let cid: CID
    public let creator: ProfileView
    public let name: String
    /// `"app.bsky.graph.defs#modlist"` or `"app.bsky.graph.defs#curatelist"`.
    public let purpose: String
    public let description: String?
    public let avatar: URL?
    public let labels: [Label]
    public let indexedAt: Date?

    public init(
        uri: ATURI,
        cid: CID,
        creator: ProfileView,
        name: String,
        purpose: String,
        description: String?,
        avatar: URL?,
        labels: [Label] = [],
        indexedAt: Date?
    ) {
        self.uri = uri
        self.cid = cid
        self.creator = creator
        self.name = name
        self.purpose = purpose
        self.description = description
        self.avatar = avatar
        self.labels = labels
        self.indexedAt = indexedAt
    }
}
