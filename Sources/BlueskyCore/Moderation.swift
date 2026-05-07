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

// MARK: - app.bsky.actor.defs#threadViewPref

/// User preferences for how a post's reply thread is sorted and grouped.
///
/// Mirrors `app.bsky.actor.defs#threadViewPref` from the AT Proto lexicon.
/// `sort` is one of `"oldest" | "newest" | "most-likes" | "random" | "hotness"`
/// — RN treats the value as a free-form string so we keep it that way and let
/// the UI map known values to localized labels.
///
/// The lexicon also carries an optional `prioritizeFollowedUsers: Bool` flag
/// that the appview honors when ordering replies. RN's *current* Settings →
/// Thread Preferences screen exposes only the sort radio + a tree-view toggle
/// (the latter rides in `lab_treeViewEnabled`, deliberately *not* modeled
/// here — it's a labs flag the SwiftUI client does not yet ship).
public struct ThreadViewPref: Sendable, Equatable {
    public var sort: String
    public var prioritizeFollowedUsers: Bool

    public init(sort: String, prioritizeFollowedUsers: Bool) {
        self.sort = sort
        self.prioritizeFollowedUsers = prioritizeFollowedUsers
    }

    /// Defaults match RN's `useThreadPreferences` fallback (`'top'`/most-likes
    /// equivalent → `"hotness"` is server-side V2; the V1 lexicon value most
    /// closely matching RN's "Top" radio is `"most-likes"`). RN's
    /// `normalizeSort` collapses anything unknown to `"top"`. We keep the
    /// canonical lexicon value here and rely on the UI to render localized
    /// labels.
    public static let defaultPref = ThreadViewPref(sort: "hotness", prioritizeFollowedUsers: true)
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
    /// `app.bsky.actor.defs#personalDetailsPref.birthDate`, if the server has
    /// one stored. Used by the Account settings hub to show / edit the user's
    /// birthday. Optional because pre-existing accounts may not have it.
    public let birthDate: Date?
    /// `app.bsky.actor.defs#threadViewPref`, if present. The Thread
    /// Preferences screen reads this to populate sort + prioritization rows;
    /// `ThreadView` reads it later (#0140) to pick the default reply sort.
    public let threadView: ThreadViewPref?

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
            let birthDate: String?
            let sort: String?
            let prioritizeFollowedUsers: Bool?
            private enum CodingKeys: String, CodingKey {
                case type = "$type", enabled, label, visibility, labelerDid, birthDate
                case feedItems = "items"
                case sort, prioritizeFollowedUsers
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

        let parser = ISO8601DateFormatter()
        self.birthDate = items
            .first { $0.type == "app.bsky.actor.defs#personalDetailsPref" }?
            .birthDate
            .flatMap { parser.date(from: $0) }

        if let pref = items.first(where: { $0.type == "app.bsky.actor.defs#threadViewPref" }) {
            self.threadView = ThreadViewPref(
                sort: pref.sort ?? ThreadViewPref.defaultPref.sort,
                prioritizeFollowedUsers: pref.prioritizeFollowedUsers
                    ?? ThreadViewPref.defaultPref.prioritizeFollowedUsers
            )
        } else {
            self.threadView = nil
        }
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

    /// Onboarding writes selected interest tags as an
    /// `app.bsky.actor.defs#interestsPref`. The lexicon carries a single
    /// `tags: string[]` field (max length 100). Mirrors RN's
    /// `agent.setInterestsPref({tags})` from `StepFinished/index.tsx`.
    public init(interests: [String]) {
        self.preferences = [AnyEncodable(_InterestsPref(tags: interests))]
    }

    private struct _InterestsPref: Encodable, Sendable {
        let tags: [String]
        private enum K: String, CodingKey { case type = "$type", tags }
        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: K.self)
            try c.encode("app.bsky.actor.defs#interestsPref", forKey: .type)
            try c.encode(tags, forKey: .tags)
        }
    }

    /// Writes a `personalDetailsPref` with the user's birth date. Mirrors the
    /// `birthDate`-only branch RN takes from `BirthDateSettingsDialog` —
    /// `agent.setPersonalDetails({birthDate})`. Note that the AT Proto spec
    /// stores birth date inside `personalDetailsPref`, not as a top-level
    /// preference; this initializer picks that single field.
    public init(birthDate: Date) {
        self.preferences = [AnyEncodable(_PersonalDetailsPref(birthDate: birthDate))]
    }

    private struct _PersonalDetailsPref: Encodable, Sendable {
        let birthDate: Date
        private enum K: String, CodingKey { case type = "$type", birthDate }
        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: K.self)
            let fmt = ISO8601DateFormatter()
            try c.encode("app.bsky.actor.defs#personalDetailsPref", forKey: .type)
            try c.encode(fmt.string(from: birthDate), forKey: .birthDate)
        }
    }

    /// Writes a `threadViewPref` carrying `sort` and `prioritizeFollowedUsers`.
    /// Mirrors RN's `agent.setThreadViewPrefs({sort, prioritizeFollowedUsers})`
    /// path used by `useSetThreadViewPreferencesMutation`.
    public init(threadView: ThreadViewPref) {
        self.preferences = [AnyEncodable(_ThreadViewPref(threadView))]
    }

    private struct _ThreadViewPref: Encodable, Sendable {
        let pref: ThreadViewPref
        private enum K: String, CodingKey { case type = "$type", sort, prioritizeFollowedUsers }
        init(_ pref: ThreadViewPref) { self.pref = pref }
        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: K.self)
            try c.encode("app.bsky.actor.defs#threadViewPref", forKey: .type)
            try c.encode(pref.sort, forKey: .sort)
            try c.encode(pref.prioritizeFollowedUsers, forKey: .prioritizeFollowedUsers)
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
