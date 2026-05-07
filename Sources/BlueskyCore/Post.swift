import Foundation

// MARK: - Self labels (com.atproto.label.defs#selfLabels)

/// A single self-applied label value, as embedded inside a `SelfLabels`
/// container. AT Proto encodes this as
/// `com.atproto.label.defs#selfLabel`. Only the `val` string is meaningful
/// here — the issuing DID, timestamp, etc. are filled in server-side when
/// the record is indexed.
public struct SelfLabelValue: Codable, Hashable, Sendable {
    /// One of the recognized self-label values, e.g. `"porn"`, `"sexual"`,
    /// `"nudity"`, `"graphic-media"`. The set of valid values for a post
    /// is curated in the composer UI; this type stays open so additional
    /// vocabularies (e.g. `"!no-unauthenticated"`) can be expressed.
    public let val: String

    public init(val: String) {
        self.val = val
    }
}

/// A `com.atproto.label.defs#selfLabels` container, attached to a record
/// (here, an `app.bsky.feed.post`) to declare its own moderation labels.
/// Encoded with an explicit `$type` discriminator so the appview accepts
/// it as a tagged union variant of the post's `labels` field.
public struct SelfLabels: Codable, Hashable, Sendable {
    public let values: [SelfLabelValue]

    public init(values: [SelfLabelValue]) {
        self.values = values
    }

    private enum CodingKeys: String, CodingKey {
        case type = "$type"
        case values
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.values = try c.decodeIfPresent([SelfLabelValue].self, forKey: .values) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode("com.atproto.label.defs#selfLabels", forKey: .type)
        try c.encode(values, forKey: .values)
    }
}

// MARK: - Threadgate (app.bsky.feed.threadgate)

/// One element in a threadgate's `allow` list. The AT Proto lexicon defines
/// four discriminated `$type`s under `app.bsky.feed.threadgate`:
///
///   - `#mentionRule` — anyone the post mentions can reply.
///   - `#followingRule` — anyone the author follows can reply.
///   - `#followerRule` — anyone who follows the author can reply.
///   - `#listRule` — anyone in the linked list (`list: ATURI`) can reply.
///
/// The semantics of the *outer* `allow` field on the record matter and are
/// asymmetric:
///
///   - `allow == nil` (field omitted) → **everyone** can reply (default).
///   - `allow == []` (empty array) → **nobody** can reply.
///   - `allow == [rule, …]` → only the union of the named rules can reply.
///
/// This mirrors RN's `threadgateRecordToAllowUISetting` /
/// `threadgateAllowUISettingToAllowRecordValue`.
public enum ThreadgateAllowRule: Codable, Hashable, Sendable {
    case mention
    case following
    case follower
    case list(ATURI)
    case unknown(String)

    private enum CodingKeys: String, CodingKey {
        case type = "$type"
        case list
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "app.bsky.feed.threadgate#mentionRule":
            self = .mention
        case "app.bsky.feed.threadgate#followingRule":
            self = .following
        case "app.bsky.feed.threadgate#followerRule":
            self = .follower
        case "app.bsky.feed.threadgate#listRule":
            let uri = try c.decode(ATURI.self, forKey: .list)
            self = .list(uri)
        default:
            self = .unknown(type)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .mention:
            try c.encode("app.bsky.feed.threadgate#mentionRule", forKey: .type)
        case .following:
            try c.encode("app.bsky.feed.threadgate#followingRule", forKey: .type)
        case .follower:
            try c.encode("app.bsky.feed.threadgate#followerRule", forKey: .type)
        case .list(let uri):
            try c.encode("app.bsky.feed.threadgate#listRule", forKey: .type)
            try c.encode(uri, forKey: .list)
        case .unknown(let t):
            try c.encode(t, forKey: .type)
        }
    }
}

/// `app.bsky.feed.threadgate` record. Restricts who can reply to the post
/// identified by `post`. The threadgate's `rkey` always matches the rkey of
/// the post it gates, so the threadgate is written into the
/// `app.bsky.feed.threadgate` collection at the same key.
///
/// `allow` is intentionally an `Optional<[ThreadgateAllowRule]>` because the
/// AT Proto lexicon distinguishes:
///
///   - omitted → everyone can reply.
///   - present but empty → nobody can reply.
///
/// Encoding preserves this distinction: `nil` omits the field; an empty array
/// is encoded as an empty array.
public struct ThreadgateRecord: Codable, Sendable {
    public let post: ATURI
    public let allow: [ThreadgateAllowRule]?
    /// Optional list of reply URIs the author has hidden from the thread.
    /// SwiftUI doesn't surface this UI yet — pass through to round-trip
    /// records fetched from the network without dropping the field.
    public let hiddenReplies: [ATURI]?
    public let createdAt: Date

    public init(
        post: ATURI,
        allow: [ThreadgateAllowRule]?,
        hiddenReplies: [ATURI]? = nil,
        createdAt: Date = .now
    ) {
        self.post = post
        self.allow = allow
        self.hiddenReplies = hiddenReplies
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case type = "$type"
        case post, allow, hiddenReplies, createdAt
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        post = try c.decode(ATURI.self, forKey: .post)
        // `allow` is meaningful when present-but-empty, so use
        // `decodeIfPresent` and preserve the array verbatim (don't coalesce
        // an empty array into `nil`).
        if c.contains(.allow) {
            allow = try c.decodeIfPresent([ThreadgateAllowRule].self, forKey: .allow)
        } else {
            allow = nil
        }
        hiddenReplies = try c.decodeIfPresent([ATURI].self, forKey: .hiddenReplies)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode("app.bsky.feed.threadgate", forKey: .type)
        try c.encode(post, forKey: .post)
        // Preserve `nil` vs empty-array distinction: `nil` omits the field
        // (everyone can reply); empty array encodes as `[]` (nobody can reply).
        if let allow {
            try c.encode(allow, forKey: .allow)
        }
        try c.encodeIfPresent(hiddenReplies, forKey: .hiddenReplies)
        try c.encode(createdAt, forKey: .createdAt)
    }
}

// MARK: - Postgate (app.bsky.feed.postgate)

/// One element in a postgate's `embeddingRules` list. The only known variant
/// today is `#disableRule`, which disables quote-posts of the post.
public enum PostgateEmbeddingRule: Codable, Hashable, Sendable {
    case disable
    case unknown(String)

    private enum CodingKeys: String, CodingKey {
        case type = "$type"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "app.bsky.feed.postgate#disableRule":
            self = .disable
        default:
            self = .unknown(type)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .disable:
            try c.encode("app.bsky.feed.postgate#disableRule", forKey: .type)
        case .unknown(let t):
            try c.encode(t, forKey: .type)
        }
    }
}

/// `app.bsky.feed.postgate` record. Restricts how the post identified by
/// `post` can be embedded (e.g. quoted). Like threadgate, the postgate's rkey
/// matches the post's rkey.
///
/// Both arrays default to an empty array per RN's `createPostgateRecord`
/// (RN ships `embeddingRules: postgate.embeddingRules || []`), and the appview
/// treats that as "no restrictions". To disable quotes, push a
/// `PostgateEmbeddingRule.disable` into `embeddingRules`.
public struct PostgateRecord: Codable, Sendable {
    public let post: ATURI
    /// URIs of quote-posts the author has detached. SwiftUI doesn't surface
    /// this UI today; preserve to round-trip records fetched from the network.
    public let detachedEmbeddingUris: [ATURI]
    public let embeddingRules: [PostgateEmbeddingRule]
    public let createdAt: Date

    public init(
        post: ATURI,
        detachedEmbeddingUris: [ATURI] = [],
        embeddingRules: [PostgateEmbeddingRule] = [],
        createdAt: Date = .now
    ) {
        self.post = post
        self.detachedEmbeddingUris = detachedEmbeddingUris
        self.embeddingRules = embeddingRules
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case type = "$type"
        case post, detachedEmbeddingUris, embeddingRules, createdAt
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        post = try c.decode(ATURI.self, forKey: .post)
        detachedEmbeddingUris = try c.decodeIfPresent([ATURI].self, forKey: .detachedEmbeddingUris) ?? []
        embeddingRules = try c.decodeIfPresent([PostgateEmbeddingRule].self, forKey: .embeddingRules) ?? []
        createdAt = try c.decode(Date.self, forKey: .createdAt)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode("app.bsky.feed.postgate", forKey: .type)
        try c.encode(post, forKey: .post)
        try c.encode(detachedEmbeddingUris, forKey: .detachedEmbeddingUris)
        try c.encode(embeddingRules, forKey: .embeddingRules)
        try c.encode(createdAt, forKey: .createdAt)
    }
}

// MARK: - Post record (app.bsky.feed.post)

/// The stored content of a post as written to the AT Protocol repo.
public struct PostRecord: Codable, Sendable {
    public let text: String
    public let facets: [RichTextFacet]?
    public let embed: Embed?
    public let reply: ReplyRef?
    /// BCP-47 language codes for the post text.
    public let langs: [String]?
    /// Self-applied moderation labels (content warnings) the author chose
    /// to attach. Encoded as `com.atproto.label.defs#selfLabels`. `nil`
    /// when no labels are selected — the field is omitted from the record
    /// entirely in that case rather than being written as an empty
    /// container.
    public let labels: SelfLabels?
    public let createdAt: Date

    public init(
        text: String,
        facets: [RichTextFacet]? = nil,
        embed: Embed? = nil,
        reply: ReplyRef? = nil,
        langs: [String]? = nil,
        labels: SelfLabels? = nil,
        createdAt: Date = .now
    ) {
        self.text = text
        self.facets = facets
        self.embed = embed
        self.reply = reply
        self.langs = langs
        self.labels = labels
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
    /// `true` if the authenticated viewer has bookmarked this post.
    public let bookmarked: Bool?

    public init(like: ATURI?, repost: ATURI?, threadMuted: Bool?, replyDisabled: Bool?, bookmarked: Bool? = nil) {
        self.like = like
        self.repost = repost
        self.threadMuted = threadMuted
        self.replyDisabled = replyDisabled
        self.bookmarked = bookmarked
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

/// The reason a post appears in a feed.
///
/// Two known variants:
///   * `reasonRepost` — the post was reposted by some actor.
///   * `reasonPin`    — the post is the actor's pinned post on their profile feed.
///
/// `reasonPin` is what surfaces the pinned post at the top of the Posts tab on
/// a profile (see #0087). The AT Proto lexicon defines it at
/// `app.bsky.feed.defs#reasonPin` and it is currently empty (no fields), but
/// the discriminator is enough: when present, the feed item is the pinned one.
/// `getAuthorFeed` only includes pinned items when the request carries
/// `includePins=true`, which RN sets only for the `posts_and_author_threads`
/// filter (the Posts tab).
public enum FeedReason: Codable, Sendable {
    /// The post was reposted by `by` at `indexedAt`.
    case repost(by: ProfileBasic, indexedAt: Date)
    /// The post is the actor's pinned post (only surfaces when the request
    /// passed `includePins=true`).
    case pin
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
        case "app.bsky.feed.defs#reasonPin":
            self = .pin
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
        case .pin:
            try c.encode("app.bsky.feed.defs#reasonPin", forKey: .type)
        case .unknown(let t):
            try c.encode(t, forKey: .type)
        }
    }
}
