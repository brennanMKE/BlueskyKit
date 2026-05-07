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

// MARK: - Get posts (app.bsky.feed.getPosts)

/// Response from `app.bsky.feed.getPosts`, which hydrates a list of post URIs
/// into their current `PostView` (with viewer state, counts, etc.).
public struct GetPostsResponse: Decodable, Sendable {
    public let posts: [PostView]

    public init(posts: [PostView]) {
        self.posts = posts
    }
}

// MARK: - Create / delete record (com.atproto.repo.*)

public struct CreateRecordRequest<T: Encodable & Sendable>: Encodable, Sendable {
    public let repo: String
    public let collection: String
    /// Optional record key. When `nil` the server allocates a TID; when
    /// non-`nil` the server writes at that exact key. This is required for
    /// companion records (threadgate / postgate) that must share an rkey
    /// with the post they gate.
    public let rkey: String?
    public let record: T

    public init(repo: String, collection: String, rkey: String? = nil, record: T) {
        self.repo = repo
        self.collection = collection
        self.rkey = rkey
        self.record = record
    }

    private enum CodingKeys: String, CodingKey {
        case repo, collection, rkey, record
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(repo, forKey: .repo)
        try c.encode(collection, forKey: .collection)
        try c.encodeIfPresent(rkey, forKey: .rkey)
        try record.encode(to: c.superEncoder(forKey: .record))
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

// MARK: - Get record (com.atproto.repo.getRecord)

/// Generic response shape for `com.atproto.repo.getRecord`. The `value` is the
/// stored record itself, decoded as the caller-supplied type. `cid` is the
/// record's content hash — useful for compare-and-swap writes via
/// `PutRecordRequest.swapRecord`.
public struct GetRecordResponse<T: Decodable & Sendable>: Decodable, Sendable {
    public let uri: String
    public let cid: String?
    public let value: T

    public init(uri: String, cid: String?, value: T) {
        self.uri = uri
        self.cid = cid
        self.value = value
    }
}

// MARK: - Profile record (app.bsky.actor.profile)

/// In-repo `app.bsky.actor.profile` record. Encoded with an explicit `$type`
/// discriminator (the appview rejects writes that omit it), and decodable so
/// callers can read the existing record (e.g. for the PWI self-label) before
/// writing it back.
///
/// Fields tracked here are the ones we currently read or write. Unknown
/// fields on the wire (e.g. `pinnedPost`, `joinedViaStarterPack`) are dropped
/// on decode and would be lost on a round-trip — only round-trip this struct
/// in flows that own all of the user-visible fields, or pass the unknown ones
/// through explicitly.
public struct ProfileRecord: Codable, Sendable {
    private let type: String
    public let displayName: String?
    public let description: String?
    /// Self-applied labels container. The PWI ("personal-web-indexing")
    /// opt-out is expressed as a `!no-unauthenticated` self-label here.
    public let labels: SelfLabels?

    private enum CodingKeys: String, CodingKey {
        case type = "$type", displayName, description, labels
    }

    public init(displayName: String?, description: String?, labels: SelfLabels? = nil) {
        self.type = "app.bsky.actor.profile"
        self.displayName = displayName
        self.description = description
        self.labels = labels
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // The server sometimes omits `$type` on the embedded value of a
        // `getRecord` response — default to the canonical NSID rather than
        // refusing to decode.
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? "app.bsky.actor.profile"
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        labels = try c.decodeIfPresent(SelfLabels.self, forKey: .labels)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encodeIfPresent(displayName, forKey: .displayName)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(labels, forKey: .labels)
    }
}

// MARK: - Notification declaration record (app.bsky.notification.declaration)

/// Activity-privacy visibility values used by the
/// `app.bsky.notification.declaration` record. Controls who is allowed to
/// subscribe to be notified about a user's posts/replies.
///
/// RN reference:
/// `Bluesky-ReactNative/src/screens/Settings/ActivityPrivacySettings.tsx` —
/// the radio group there writes one of `followers | mutuals | none`.
/// (`AppBskyNotificationDeclaration.Record["allowSubscriptions"]` from the
/// `@atproto/api` package.)
public enum AllowSubscriptions: String, Codable, Sendable, Hashable, CaseIterable {
    /// Anyone who follows the user can subscribe to their activity.
    case followers
    /// Only mutuals (followers the user also follows) can subscribe.
    case mutuals
    /// No one can subscribe.
    case none
}

/// In-repo `app.bsky.notification.declaration` record. Stored at
/// `repo=<did>, collection=app.bsky.notification.declaration, rkey=self`.
///
/// Today this record only carries `allowSubscriptions` — the activity-privacy
/// visibility setting written by the Activity Privacy settings screen.
/// Encoded with an explicit `$type` discriminator (the appview rejects writes
/// that omit it). On decode, `$type` is optional because some `getRecord`
/// payloads omit it on the embedded value.
public struct NotificationDeclarationRecord: Codable, Sendable {
    private let type: String
    public let allowSubscriptions: AllowSubscriptions

    private enum CodingKeys: String, CodingKey {
        case type = "$type", allowSubscriptions
    }

    public init(allowSubscriptions: AllowSubscriptions) {
        self.type = "app.bsky.notification.declaration"
        self.allowSubscriptions = allowSubscriptions
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decodeIfPresent(String.self, forKey: .type)
            ?? "app.bsky.notification.declaration"
        // Tolerate an unknown / future value by falling back to RN's default
        // (`followers`). Mirrors `useNotificationDeclarationQuery`'s
        // "Could not locate record" branch which also returns `followers`.
        if let raw = try c.decodeIfPresent(String.self, forKey: .allowSubscriptions),
           let parsed = AllowSubscriptions(rawValue: raw) {
            allowSubscriptions = parsed
        } else {
            allowSubscriptions = .followers
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encode(allowSubscriptions, forKey: .allowSubscriptions)
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
