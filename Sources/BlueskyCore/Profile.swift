import Foundation

// MARK: - Decoding helpers

/// Decode a URL field that the server may send as an empty string.
/// Returns `nil` for missing, null, or empty-string values.
private func decodeURL<K: CodingKey>(
    _ container: KeyedDecodingContainer<K>,
    forKey key: K
) throws -> URL? {
    guard let raw = try container.decodeIfPresent(String.self, forKey: key),
          !raw.isEmpty else { return nil }
    return URL(string: raw)
}

// MARK: - Moderation label

/// An `app.bsky.label.defs#label` applied to a record or account.
public struct Label: Codable, Hashable, Sendable {
    /// DID of the labeler that issued this label.
    public let src: DID
    /// AT-URI of the labeled record (or DID for account-level labels).
    public let uri: String
    /// Label value, e.g. `"porn"`, `"gore"`, `"!warn"`.
    public let val: String
    /// `true` if this label negates a previously applied label.
    public let neg: Bool?
    /// Creation timestamp.
    public let cts: Date

    public init(src: DID, uri: String, val: String, neg: Bool?, cts: Date) {
        self.src = src
        self.uri = uri
        self.val = val
        self.neg = neg
        self.cts = cts
    }
}

// MARK: - Profile types (app.bsky.actor.defs)

/// Minimal actor view used inside post/notification payloads.
public struct ProfileBasic: Codable, Hashable, Sendable {
    public let did: DID
    public let handle: Handle
    public let displayName: String?
    /// CDN URL for the avatar image.
    public let avatar: URL?
    public let labels: [Label]

    public init(
        did: DID,
        handle: Handle,
        displayName: String?,
        avatar: URL?,
        labels: [Label] = []
    ) {
        self.did = did
        self.handle = handle
        self.displayName = displayName
        self.avatar = avatar
        self.labels = labels
    }

    private enum CodingKeys: String, CodingKey {
        case did, handle, displayName, avatar, labels
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        did = try c.decode(DID.self, forKey: .did)
        handle = try c.decode(Handle.self, forKey: .handle)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        avatar = try decodeURL(c, forKey: .avatar)
        labels = try c.decodeIfPresent([Label].self, forKey: .labels) ?? []
    }
}

/// Profile view with bio and viewer-state fields (used in follow lists, search results).
public struct ProfileView: Codable, Hashable, Sendable {
    public let did: DID
    public let handle: Handle
    public let displayName: String?
    public let description: String?
    public let avatar: URL?
    public let labels: [Label]
    public let indexedAt: Date?
    public let viewer: ProfileViewerState?

    public init(
        did: DID,
        handle: Handle,
        displayName: String?,
        description: String?,
        avatar: URL?,
        labels: [Label] = [],
        indexedAt: Date?,
        viewer: ProfileViewerState?
    ) {
        self.did = did
        self.handle = handle
        self.displayName = displayName
        self.description = description
        self.avatar = avatar
        self.labels = labels
        self.indexedAt = indexedAt
        self.viewer = viewer
    }

    private enum CodingKeys: String, CodingKey {
        case did, handle, displayName, description, avatar, labels, indexedAt, viewer
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        did = try c.decode(DID.self, forKey: .did)
        handle = try c.decode(Handle.self, forKey: .handle)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        avatar = try decodeURL(c, forKey: .avatar)
        labels = try c.decodeIfPresent([Label].self, forKey: .labels) ?? []
        indexedAt = try c.decodeIfPresent(Date.self, forKey: .indexedAt)
        viewer = try c.decodeIfPresent(ProfileViewerState.self, forKey: .viewer)
    }
}

/// Full profile returned by `app.bsky.actor.getProfile`.
public struct ProfileDetailed: Codable, Sendable {
    public let did: DID
    public let handle: Handle
    public let displayName: String?
    public let description: String?
    public let avatar: URL?
    public let banner: URL?
    public let followersCount: Int
    public let followsCount: Int
    public let postsCount: Int
    public let labels: [Label]
    public let createdAt: Date?
    public let indexedAt: Date?
    public let viewer: ProfileViewerState?

    public init(
        did: DID,
        handle: Handle,
        displayName: String?,
        description: String?,
        avatar: URL?,
        banner: URL?,
        followersCount: Int,
        followsCount: Int,
        postsCount: Int,
        labels: [Label] = [],
        createdAt: Date?,
        indexedAt: Date?,
        viewer: ProfileViewerState?
    ) {
        self.did = did
        self.handle = handle
        self.displayName = displayName
        self.description = description
        self.avatar = avatar
        self.banner = banner
        self.followersCount = followersCount
        self.followsCount = followsCount
        self.postsCount = postsCount
        self.labels = labels
        self.createdAt = createdAt
        self.indexedAt = indexedAt
        self.viewer = viewer
    }

    private enum CodingKeys: String, CodingKey {
        case did, handle, displayName, description, avatar, banner
        case followersCount, followsCount, postsCount
        case labels, createdAt, indexedAt, viewer
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        did = try c.decode(DID.self, forKey: .did)
        handle = try c.decode(Handle.self, forKey: .handle)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        avatar = try decodeURL(c, forKey: .avatar)
        banner = try decodeURL(c, forKey: .banner)
        followersCount = try c.decodeIfPresent(Int.self, forKey: .followersCount) ?? 0
        followsCount = try c.decodeIfPresent(Int.self, forKey: .followsCount) ?? 0
        postsCount = try c.decodeIfPresent(Int.self, forKey: .postsCount) ?? 0
        labels = try c.decodeIfPresent([Label].self, forKey: .labels) ?? []
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        indexedAt = try c.decodeIfPresent(Date.self, forKey: .indexedAt)
        viewer = try c.decodeIfPresent(ProfileViewerState.self, forKey: .viewer)
    }
}

// MARK: - Viewer state

/// Relationship between the authenticated viewer and another account.
public struct ProfileViewerState: Codable, Hashable, Sendable {
    public let muted: Bool?
    public let mutedByList: ListBasic?
    public let blockedBy: Bool?
    /// AT-URI of the viewer's block record, if blocking.
    public let blocking: ATURI?
    /// AT-URI of the viewer's follow record, if following.
    public let following: ATURI?
    /// AT-URI of the other account's follow record, if they follow the viewer.
    public let followedBy: ATURI?

    public init(
        muted: Bool?,
        mutedByList: ListBasic?,
        blockedBy: Bool?,
        blocking: ATURI?,
        following: ATURI?,
        followedBy: ATURI?
    ) {
        self.muted = muted
        self.mutedByList = mutedByList
        self.blockedBy = blockedBy
        self.blocking = blocking
        self.following = following
        self.followedBy = followedBy
    }
}

// MARK: - List reference (app.bsky.graph.defs#listBasicView)

/// Lightweight list reference used inside viewer state and moderation contexts.
public struct ListBasic: Codable, Hashable, Sendable {
    public let uri: ATURI
    public let cid: CID
    public let name: String
    /// `"app.bsky.graph.defs#modlist"` or `"app.bsky.graph.defs#curatelist"`.
    public let purpose: String
    public let avatar: URL?
    public let labels: [Label]

    public init(
        uri: ATURI,
        cid: CID,
        name: String,
        purpose: String,
        avatar: URL?,
        labels: [Label] = []
    ) {
        self.uri = uri
        self.cid = cid
        self.name = name
        self.purpose = purpose
        self.avatar = avatar
        self.labels = labels
    }
}
