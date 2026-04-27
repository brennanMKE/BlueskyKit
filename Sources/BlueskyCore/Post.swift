import Foundation

// MARK: - Post record (app.bsky.feed.post)

/// The stored content of a post as written to the AT Protocol repo.
public struct PostRecord: Codable, Sendable {
    public let text: String
    public let facets: [RichTextFacet]?
    public let embed: Embed?
    public let reply: ReplyRef?
    /// BCP-47 language codes for the post text.
    public let langs: [String]?
    public let createdAt: Date

    public init(
        text: String,
        facets: [RichTextFacet]? = nil,
        embed: Embed? = nil,
        reply: ReplyRef? = nil,
        langs: [String]? = nil,
        createdAt: Date = .now
    ) {
        self.text = text
        self.facets = facets
        self.embed = embed
        self.reply = reply
        self.langs = langs
        self.createdAt = createdAt
    }
}

// MARK: - Reply references

/// Root and parent pointers stored inside a reply post record.
public struct ReplyRef: Codable, Sendable {
    public let root: PostRef
    public let parent: PostRef

    public init(root: PostRef, parent: PostRef) {
        self.root = root
        self.parent = parent
    }
}

/// A minimal {uri, cid} pair pointing to another post.
public struct PostRef: Codable, Sendable {
    public let uri: ATURI
    public let cid: CID

    public init(uri: ATURI, cid: CID) {
        self.uri = uri
        self.cid = cid
    }
}

// MARK: - Post view (app.bsky.feed.defs#postView)

/// The full post view returned by feed and thread endpoints.
public struct PostView: Codable, Sendable {
    public let uri: ATURI
    public let cid: CID
    public let author: ProfileBasic
    public let record: PostRecord
    public let embed: EmbedView?
    public let replyCount: Int
    public let repostCount: Int
    public let likeCount: Int
    public let quoteCount: Int
    public let indexedAt: Date
    public let labels: [Label]
    public let viewer: PostViewerState?

    public init(
        uri: ATURI,
        cid: CID,
        author: ProfileBasic,
        record: PostRecord,
        embed: EmbedView?,
        replyCount: Int,
        repostCount: Int,
        likeCount: Int,
        quoteCount: Int,
        indexedAt: Date,
        labels: [Label] = [],
        viewer: PostViewerState?
    ) {
        self.uri = uri
        self.cid = cid
        self.author = author
        self.record = record
        self.embed = embed
        self.replyCount = replyCount
        self.repostCount = repostCount
        self.likeCount = likeCount
        self.quoteCount = quoteCount
        self.indexedAt = indexedAt
        self.labels = labels
        self.viewer = viewer
    }

    private enum CodingKeys: String, CodingKey {
        case uri, cid, author, record, embed
        case replyCount, repostCount, likeCount, quoteCount
        case indexedAt, labels, viewer
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uri = try c.decode(ATURI.self, forKey: .uri)
        cid = try c.decode(CID.self, forKey: .cid)
        author = try c.decode(ProfileBasic.self, forKey: .author)
        record = try c.decode(PostRecord.self, forKey: .record)
        embed = try c.decodeIfPresent(EmbedView.self, forKey: .embed)
        replyCount = try c.decodeIfPresent(Int.self, forKey: .replyCount) ?? 0
        repostCount = try c.decodeIfPresent(Int.self, forKey: .repostCount) ?? 0
        likeCount = try c.decodeIfPresent(Int.self, forKey: .likeCount) ?? 0
        quoteCount = try c.decodeIfPresent(Int.self, forKey: .quoteCount) ?? 0
        indexedAt = try c.decode(Date.self, forKey: .indexedAt)
        labels = try c.decodeIfPresent([Label].self, forKey: .labels) ?? []
        viewer = try c.decodeIfPresent(PostViewerState.self, forKey: .viewer)
    }
}

/// The authenticated viewer's relationship to a post (liked, reposted, etc.).
public struct PostViewerState: Codable, Sendable {
    /// AT-URI of the viewer's like record, if liked.
    public let like: ATURI?
    /// AT-URI of the viewer's repost record, if reposted.
    public let repost: ATURI?
    public let threadMuted: Bool?
    public let replyDisabled: Bool?

    public init(like: ATURI?, repost: ATURI?, threadMuted: Bool?, replyDisabled: Bool?) {
        self.like = like
        self.repost = repost
        self.threadMuted = threadMuted
        self.replyDisabled = replyDisabled
    }
}

// MARK: - Feed view post (app.bsky.feed.defs#feedViewPost)

/// A post as it appears in a feed, with optional reply context and repost reason.
public struct FeedViewPost: Codable, Sendable {
    public let post: PostView
    public let reply: ReplyContext?
    /// Non-nil when this post appears because someone reposted it.
    public let reason: FeedReason?

    public init(post: PostView, reply: ReplyContext?, reason: FeedReason?) {
        self.post = post
        self.reply = reply
        self.reason = reason
    }
}

/// The root and parent posts shown above a reply in a feed.
public struct ReplyContext: Codable, Sendable {
    public let root: PostView?
    public let parent: PostView?

    public init(root: PostView?, parent: PostView?) {
        self.root = root
        self.parent = parent
    }
}

/// The reason a post appears in a feed (currently only repost).
public enum FeedReason: Codable, Sendable {
    /// The post was reposted by `by` at `indexedAt`.
    case repost(by: ProfileBasic, indexedAt: Date)
    case unknown(String)

    private enum CodingKeys: String, CodingKey {
        case type = "$type"
        case by, indexedAt
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "app.bsky.feed.defs#reasonRepost":
            let by = try c.decode(ProfileBasic.self, forKey: .by)
            let indexedAt = try c.decode(Date.self, forKey: .indexedAt)
            self = .repost(by: by, indexedAt: indexedAt)
        default:
            self = .unknown(type)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .repost(let by, let indexedAt):
            try c.encode("app.bsky.feed.defs#reasonRepost", forKey: .type)
            try c.encode(by, forKey: .by)
            try c.encode(indexedAt, forKey: .indexedAt)
        case .unknown(let t):
            try c.encode(t, forKey: .type)
        }
    }
}
