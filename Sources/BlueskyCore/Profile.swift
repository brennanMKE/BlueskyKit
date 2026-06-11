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

// MARK: - Verification (app.bsky.actor.defs#verificationState)

/// Bluesky's user-verification status, surfaced inline on every actor view.
///
/// AT Proto encodes this as `app.bsky.actor.defs#verificationState`. The two
/// status fields use the enumeration `valid | invalid | none`. We keep the raw
/// strings as `String` (not an enum) to stay forward-compatible with new
/// statuses that may appear server-side.
public struct VerificationState: Codable, Hashable, Sendable {
    /// `"valid"` when the account is currently verified by at least one
    /// trusted verifier; `"invalid"` if a previously valid verification has
    /// been revoked; `"none"` (or absent) otherwise.
    public let verifiedStatus: String
    /// `"valid"` when the account itself is a trusted verifier;
    /// `"none"` otherwise.
    public let trustedVerifierStatus: String

    public init(verifiedStatus: String, trustedVerifierStatus: String) {
        self.verifiedStatus = verifiedStatus
        self.trustedVerifierStatus = trustedVerifierStatus
    }

    /// `true` when the badge should render — verifiedStatus or
    /// trustedVerifierStatus is `"valid"`. Mirrors RN's
    /// `useSimpleVerificationState` (excluding the user's hide-badges pref,
    /// which is applied at the call site).
    public var isVerified: Bool {
        verifiedStatus == "valid" || trustedVerifierStatus == "valid"
    }

    /// `true` when this account is itself a trusted verifier (drives the
    /// scalloped-edge variant of the badge — not yet rendered, but exposed
    /// here so callers can branch later).
    public var isVerifier: Bool {
        trustedVerifierStatus == "valid" || trustedVerifierStatus == "invalid"
    }

    private enum CodingKeys: String, CodingKey {
        case verifiedStatus, trustedVerifierStatus
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        verifiedStatus = try c.decodeIfPresent(String.self, forKey: .verifiedStatus) ?? "none"
        trustedVerifierStatus = try c.decodeIfPresent(String.self, forKey: .trustedVerifierStatus) ?? "none"
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
    /// Verification state (`app.bsky.actor.defs#verificationState`).
    /// `nil` when the server omits the field — treat as unverified.
    public let verification: VerificationState?

    public init(
        did: DID,
        handle: Handle,
        displayName: String?,
        avatar: URL?,
        labels: [Label] = [],
        verification: VerificationState? = nil
    ) {
        self.did = did
        self.handle = handle
        self.displayName = displayName
        self.avatar = avatar
        self.labels = labels
        self.verification = verification
    }

    private enum CodingKeys: String, CodingKey {
        case did, handle, displayName, avatar, labels, verification
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        did = try c.decode(DID.self, forKey: .did)
        handle = try c.decode(Handle.self, forKey: .handle)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        avatar = try decodeURL(c, forKey: .avatar)
        labels = try c.decodeIfPresent([Label].self, forKey: .labels) ?? []
        verification = try c.decodeIfPresent(VerificationState.self, forKey: .verification)
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
    public let verification: VerificationState?

    public init(
        did: DID,
        handle: Handle,
        displayName: String?,
        description: String?,
        avatar: URL?,
        labels: [Label] = [],
        indexedAt: Date?,
        viewer: ProfileViewerState?,
        verification: VerificationState? = nil
    ) {
        self.did = did
        self.handle = handle
        self.displayName = displayName
        self.description = description
        self.avatar = avatar
        self.labels = labels
        self.indexedAt = indexedAt
        self.viewer = viewer
        self.verification = verification
    }

    private enum CodingKeys: String, CodingKey {
        case did, handle, displayName, description, avatar, labels, indexedAt, viewer, verification
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
        verification = try c.decodeIfPresent(VerificationState.self, forKey: .verification)
    }
}

/// Associated-resource counts on a detailed profile
/// (`app.bsky.actor.defs#profileAssociated`). RN uses these to gate
/// profile tabs — e.g. the Starter Packs tab shows when
/// `associated.starterPacks > 0` (#0206).
public struct ProfileAssociated: Codable, Hashable, Sendable {
    public let lists: Int
    public let feedgens: Int
    public let starterPacks: Int
    public let labeler: Bool?

    public init(lists: Int = 0, feedgens: Int = 0, starterPacks: Int = 0, labeler: Bool? = nil) {
        self.lists = lists
        self.feedgens = feedgens
        self.starterPacks = starterPacks
        self.labeler = labeler
    }

    private enum CodingKeys: String, CodingKey {
        case lists, feedgens, starterPacks, labeler
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lists = try c.decodeIfPresent(Int.self, forKey: .lists) ?? 0
        feedgens = try c.decodeIfPresent(Int.self, forKey: .feedgens) ?? 0
        starterPacks = try c.decodeIfPresent(Int.self, forKey: .starterPacks) ?? 0
        labeler = try c.decodeIfPresent(Bool.self, forKey: .labeler)
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
    public let associated: ProfileAssociated?
    public let createdAt: Date?
    public let indexedAt: Date?
    public let viewer: ProfileViewerState?
    public let verification: VerificationState?

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
        associated: ProfileAssociated? = nil,
        createdAt: Date?,
        indexedAt: Date?,
        viewer: ProfileViewerState?,
        verification: VerificationState? = nil
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
        self.associated = associated
        self.createdAt = createdAt
        self.indexedAt = indexedAt
        self.viewer = viewer
        self.verification = verification
    }

    private enum CodingKeys: String, CodingKey {
        case did, handle, displayName, description, avatar, banner
        case followersCount, followsCount, postsCount
        case labels, associated, createdAt, indexedAt, viewer, verification
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
        associated = try c.decodeIfPresent(ProfileAssociated.self, forKey: .associated)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        indexedAt = try c.decodeIfPresent(Date.self, forKey: .indexedAt)
        viewer = try c.decodeIfPresent(ProfileViewerState.self, forKey: .viewer)
        verification = try c.decodeIfPresent(VerificationState.self, forKey: .verification)
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
