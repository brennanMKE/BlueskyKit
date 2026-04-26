import Foundation

// MARK: - com.atproto.moderation.createReport

/// Subject pointing to an entire account (repo).
public struct ReportSubjectRepo: Encodable, Sendable {
    public let did: DID

    private enum CodingKeys: String, CodingKey {
        case type = "$type", did
    }

    public init(did: DID) {
        self.did = did
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode("com.atproto.admin.defs#repoRef", forKey: .type)
        try c.encode(did, forKey: .did)
    }
}

/// Subject pointing to a specific record.
public struct ReportSubjectRecord: Encodable, Sendable {
    public let uri: ATURI
    public let cid: CID

    private enum CodingKeys: String, CodingKey {
        case type = "$type", uri, cid
    }

    public init(uri: ATURI, cid: CID) {
        self.uri = uri
        self.cid = cid
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode("com.atproto.repo.strongRef", forKey: .type)
        try c.encode(uri, forKey: .uri)
        try c.encode(cid, forKey: .cid)
    }
}

public struct CreateReportRequest: Encodable, Sendable {
    /// e.g. `"com.atproto.moderation.defs#reasonSpam"` or `"#reasonViolation"`.
    public let reasonType: String
    public let reason: String?
    public let subject: AnyEncodable

    public init(reasonType: String, reason: String? = nil, subject: some Encodable & Sendable) {
        self.reasonType = reasonType
        self.reason = reason
        self.subject = AnyEncodable(subject)
    }
}

public struct CreateReportResponse: Codable, Sendable {
    public let id: Int
    public let reasonType: String
    public let reason: String?
    public let reportedBy: DID
    public let createdAt: Date

    public init(id: Int, reasonType: String, reason: String?, reportedBy: DID, createdAt: Date) {
        self.id = id
        self.reasonType = reasonType
        self.reason = reason
        self.reportedBy = reportedBy
        self.createdAt = createdAt
    }
}

// MARK: - app.bsky.graph.getList

public struct GetListResponse: Codable, Sendable {
    public let list: ListView
    public let items: [ListItemView]
    public let cursor: Cursor?

    public init(list: ListView, items: [ListItemView], cursor: Cursor?) {
        self.list = list
        self.items = items
        self.cursor = cursor
    }
}

public struct ListItemView: Codable, Sendable {
    public let uri: ATURI
    public let subject: ProfileView

    public init(uri: ATURI, subject: ProfileView) {
        self.uri = uri
        self.subject = subject
    }
}

// MARK: - Mute / unmute actor list

public struct ListMuteRequest: Encodable, Sendable {
    public let list: String
    public init(list: ATURI) { self.list = list.rawValue }
}

// MARK: - Actor preferences (app.bsky.actor.getPreferences / putPreferences)

public struct ContentLabelPref: Sendable {
    public let label: String
    public var visibility: String
    public let labelerDid: DID?

    public init(label: String, visibility: String, labelerDid: DID? = nil) {
        self.label = label
        self.visibility = visibility
        self.labelerDid = labelerDid
    }
}

// MARK: - app.bsky.actor.defs#savedFeed

public struct SavedFeed: Codable, Sendable, Identifiable {
    public let id: String
    /// `"feed"`, `"list"`, or `"timeline"`.
    public let type: String
    /// AT-URI for feed/list, or `"following"` for the timeline.
    public let value: String
    public var pinned: Bool

    public init(id: String, type: String, value: String, pinned: Bool) {
        self.id = id
        self.type = type
        self.value = value
        self.pinned = pinned
    }
}

public struct GetPreferencesResponse: Decodable, Sendable {
    public let adultContentEnabled: Bool
    public let contentLabels: [ContentLabelPref]
    public let savedFeeds: [SavedFeed]

    private enum OuterKeys: String, CodingKey { case preferences }

    public init(from decoder: any Decoder) throws {
        struct FeedItemHelper: Decodable {
            let id: String
            let type: String
            let value: String
            let pinned: Bool
        }
        struct Item: Decodable {
            let type: String
            let enabled: Bool?
            let label: String?
            let visibility: String?
            let labelerDid: DID?
            let feedItems: [FeedItemHelper]?
            private enum CodingKeys: String, CodingKey {
                case type = "$type", enabled, label, visibility, labelerDid
                case feedItems = "items"
            }
        }

        let outer = try decoder.container(keyedBy: OuterKeys.self)
        let items = try outer.decode([Item].self, forKey: .preferences)

        self.adultContentEnabled = items
            .first { $0.type == "app.bsky.actor.defs#adultContentPref" }
            .flatMap { $0.enabled } ?? false

        self.contentLabels = items
            .filter { $0.type == "app.bsky.actor.defs#contentLabelPref" }
            .compactMap { item in
                guard let label = item.label, let vis = item.visibility else { return nil }
                return ContentLabelPref(label: label, visibility: vis, labelerDid: item.labelerDid)
            }

        self.savedFeeds = items
            .first { $0.type == "app.bsky.actor.defs#savedFeedsPrefV2" }?
            .feedItems?
            .map { SavedFeed(id: $0.id, type: $0.type, value: $0.value, pinned: $0.pinned) }
            ?? []
    }
}

public struct PutPreferencesRequest: Encodable, Sendable {
    public let preferences: [AnyEncodable]

    public init(adultContentEnabled: Bool, contentLabels: [ContentLabelPref]) {
        var prefs: [AnyEncodable] = [AnyEncodable(_AdultPref(enabled: adultContentEnabled))]
        prefs += contentLabels.map { AnyEncodable(_LabelPref($0)) }
        self.preferences = prefs
    }

    private struct _AdultPref: Encodable, Sendable {
        let enabled: Bool
        private enum K: String, CodingKey { case type = "$type", enabled }
        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: K.self)
            try c.encode("app.bsky.actor.defs#adultContentPref", forKey: .type)
            try c.encode(enabled, forKey: .enabled)
        }
    }

    private struct _LabelPref: Encodable, Sendable {
        let pref: ContentLabelPref
        private enum K: String, CodingKey { case type = "$type", label, visibility, labelerDid }
        init(_ pref: ContentLabelPref) { self.pref = pref }
        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: K.self)
            try c.encode("app.bsky.actor.defs#contentLabelPref", forKey: .type)
            try c.encode(pref.label, forKey: .label)
            try c.encode(pref.visibility, forKey: .visibility)
            try c.encodeIfPresent(pref.labelerDid, forKey: .labelerDid)
        }
    }

    public init(savedFeeds: [SavedFeed]) {
        self.preferences = [AnyEncodable(_SavedFeedsPrefV2(items: savedFeeds))]
    }

    private struct _SavedFeedsPrefV2: Encodable, Sendable {
        let items: [SavedFeed]
        private enum K: String, CodingKey { case type = "$type", items }
        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: K.self)
            try c.encode("app.bsky.actor.defs#savedFeedsPrefV2", forKey: .type)
            try c.encode(items, forKey: .items)
        }
    }
}

// MARK: - app.bsky.labeler.getServices response

public struct GetLabelerServicesResponse: Decodable, Sendable {
    public let views: [LabelerView]
}

// MARK: - app.bsky.labeler.defs#labelerView

/// A labeler service view returned by `app.bsky.labeler.getServices`.
public struct LabelerView: Codable, Sendable {
    public let uri: ATURI
    public let cid: CID
    public let creator: ProfileView
    public let likeCount: Int?
    public let labels: [Label]
    public let indexedAt: Date

    public init(
        uri: ATURI,
        cid: CID,
        creator: ProfileView,
        likeCount: Int?,
        labels: [Label] = [],
        indexedAt: Date
    ) {
        self.uri = uri
        self.cid = cid
        self.creator = creator
        self.likeCount = likeCount
        self.labels = labels
        self.indexedAt = indexedAt
    }
}
