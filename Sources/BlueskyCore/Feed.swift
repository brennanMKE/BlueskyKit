import Foundation

// MARK: - Feed response (getTimeline, getFeed, getAuthorFeed)

public struct FeedResponse: Decodable, Sendable {
    public let feed: [FeedViewPost]
    public let cursor: String?
}

// MARK: - Post thread (app.bsky.feed.getPostThread)

public indirect enum ThreadViewPost: Decodable, Sendable {
    case post(ThreadPost)
    case notFound(uri: ATURI)
    case blocked(uri: ATURI)
    case unknown(String)

    private enum CodingKeys: String, CodingKey { case type = "$type" }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "app.bsky.feed.defs#threadViewPost":
            self = .post(try ThreadPost(from: decoder))
        case "app.bsky.feed.defs#notFoundPost":
            struct NF: Decodable { let uri: ATURI }
            self = .notFound(uri: try NF(from: decoder).uri)
        case "app.bsky.feed.defs#blockedPost":
            struct BL: Decodable { let uri: ATURI }
            self = .blocked(uri: try BL(from: decoder).uri)
        default:
            self = .unknown(type)
        }
    }
}

public struct ThreadPost: Decodable, Sendable {
    public let post: PostView
    public let parent: ThreadViewPost?
    public let replies: [ThreadViewPost]?
}

public struct GetPostThreadResponse: Decodable, Sendable {
    public let thread: ThreadViewPost
}

// MARK: - Create / delete record (com.atproto.repo.*)

public struct CreateRecordRequest<T: Encodable & Sendable>: Encodable, Sendable {
    public let repo: String
    public let collection: String
    public let record: T

    public init(repo: String, collection: String, record: T) {
        self.repo = repo
        self.collection = collection
        self.record = record
    }
}

public struct CreateRecordResponse: Decodable, Sendable {
    public let uri: ATURI
    public let cid: CID
}

public struct DeleteRecordRequest: Encodable, Sendable {
    public let repo: String
    public let collection: String
    public let rkey: String

    public init(repo: String, collection: String, rkey: String) {
        self.repo = repo
        self.collection = collection
        self.rkey = rkey
    }
}

/// Empty decodable used for AT Protocol operations that return `{}` with no meaningful payload.
public struct EmptyResponse: Decodable, Sendable {
    public init() {}
    public init(from decoder: any Decoder) throws {}
}

// MARK: - Put record (com.atproto.repo.putRecord)

public struct PutRecordRequest<T: Encodable & Sendable>: Encodable, Sendable {
    public let repo: String
    public let collection: String
    public let rkey: String
    public let record: T

    public init(repo: String, collection: String, rkey: String, record: T) {
        self.repo = repo
        self.collection = collection
        self.rkey = rkey
        self.record = record
    }
}

// MARK: - Profile record (app.bsky.actor.profile)

public struct ProfileRecord: Encodable, Sendable {
    private let type: String = "app.bsky.actor.profile"
    public let displayName: String?
    public let description: String?

    private enum CodingKeys: String, CodingKey {
        case type = "$type", displayName, description
    }

    public init(displayName: String?, description: String?) {
        self.displayName = displayName
        self.description = description
    }
}

// MARK: - Like record (app.bsky.feed.like)

public struct LikeRecord: Encodable, Sendable {
    private let type: String = "app.bsky.feed.like"
    public let subject: PostRef
    public let createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case type = "$type", subject, createdAt
    }

    public init(subject: PostRef, createdAt: Date = .now) {
        self.subject = subject
        self.createdAt = createdAt
    }
}

// MARK: - Repost record (app.bsky.feed.repost)

public struct RepostRecord: Encodable, Sendable {
    private let type: String = "app.bsky.feed.repost"
    public let subject: PostRef
    public let createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case type = "$type", subject, createdAt
    }

    public init(subject: PostRef, createdAt: Date = .now) {
        self.subject = subject
        self.createdAt = createdAt
    }
}
