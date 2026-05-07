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

// MARK: - app.bsky.actor.defs#feedViewPref

/// User preferences for how a feed (`feed: 'home'` is the Following timeline)
/// hides replies, reposts, and quote posts.
///
/// Mirrors `app.bsky.actor.defs#feedViewPref` from the AT Proto lexicon. The
/// preference is keyed by `feed`; the Following-feed settings screen reads /
/// writes the entry whose `feed == "home"` (renamed from "home" → "Following"
/// at the product level, but the lexicon key stayed `home`).
///
/// The lexicon also defines `hideRepliesByUnfollowed: Bool` and
/// `hideRepliesByLikeCount: Int`. RN's `DEFAULT_HOME_FEED_PREFS` flags both as
/// **"Legacy, ignored"** and the live RN screen does not expose either field,
/// so we model them on the value type for round-tripping but do not surface
/// them in the SwiftUI Settings UI.
public struct FeedViewPref: Sendable, Equatable {
    /// Feed identifier — `"home"` for the Following timeline.
    public var feed: String
    public var hideReplies: Bool
    public var hideRepliesByUnfollowed: Bool
    public var hideRepliesByLikeCount: Int
    public var hideReposts: Bool
    public var hideQuotePosts: Bool

    public init(
        feed: String,
        hideReplies: Bool,
        hideRepliesByUnfollowed: Bool,
        hideRepliesByLikeCount: Int,
        hideReposts: Bool,
        hideQuotePosts: Bool
    ) {
        self.feed = feed
        self.hideReplies = hideReplies
        self.hideRepliesByUnfollowed = hideRepliesByUnfollowed
        self.hideRepliesByLikeCount = hideRepliesByLikeCount
        self.hideReposts = hideReposts
        self.hideQuotePosts = hideQuotePosts
    }

    /// Defaults from RN's `DEFAULT_HOME_FEED_PREFS`. `hideRepliesByUnfollowed`
    /// is `true` and `hideRepliesByLikeCount` is `0` in RN's defaults but both
    /// are commented as legacy / ignored.
    public static let defaultHome = FeedViewPref(
        feed: "home",
        hideReplies: false,
        hideRepliesByUnfollowed: true,
        hideRepliesByLikeCount: 0,
        hideReposts: false,
        hideQuotePosts: false
    )
}

// MARK: - app.bsky.actor.defs#mutedWord

/// A single muted-word entry persisted under
/// `app.bsky.actor.defs#mutedWordsPref`. Mirrors `AppBskyActorDefs.MutedWord`
/// from the AT Proto SDK.
///
/// `targets` is one or more of `"content"` (match against post text) and
/// `"tag"` (match against post hashtags). RN's add-form always includes
/// `"tag"` and conditionally adds `"content"`, so a "Tags only" entry
/// has `targets == ["tag"]` and a "Text & tags" entry has both.
///
/// `actorTarget` defaults to `"all"`; setting it to `"exclude-following"`
/// exempts users the viewer follows from the mute. Optional in the lexicon
/// for forward compatibility.
///
/// `expiresAt` is an ISO-8601 timestamp. `nil` means "forever". RN renders
/// expired entries with a "Renew" affordance; this client surfaces an
/// "Expired" pill and lets the user delete or recreate.
///
/// `id` is server-issued and used by the SDK's update path. We round-trip
/// it but don't generate one client-side; the server will assign one when
/// the entry is upserted.
public struct MutedWord: Codable, Sendable, Equatable {
    public var id: String?
    public var value: String
    public var targets: [String]
    public var actorTarget: String?
    public var expiresAt: Date?

    public init(
        id: String? = nil,
        value: String,
        targets: [String],
        actorTarget: String? = nil,
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.value = value
        self.targets = targets
        self.actorTarget = actorTarget
        self.expiresAt = expiresAt
    }

    /// `true` if `expiresAt` is in the past (relative to `now`).
    public func isExpired(now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt < now
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
    /// `app.bsky.actor.defs#personalDetailsPref.birthDate`, if the server has
    /// one stored. Used by the Account settings hub to show / edit the user's
    /// birthday. Optional because pre-existing accounts may not have it.
    public let birthDate: Date?
    /// `app.bsky.actor.defs#threadViewPref`, if present. The Thread
    /// Preferences screen reads this to populate sort + prioritization rows;
    /// `ThreadView` reads it later (#0140) to pick the default reply sort.
    public let threadView: ThreadViewPref?
    /// All `app.bsky.actor.defs#feedViewPref` entries returned by
    /// `getPreferences`, keyed by their `feed` field. Multiple instances may
    /// coexist (one per saved feed). The Following-feed Settings screen reads
    /// `feedViews["home"]`; the home timeline view models can consult the
    /// same dictionary to honor `hideReplies` / `hideReposts` /
    /// `hideQuotePosts` globally (cross-cuts #0017).
    public let feedViews: [String: FeedViewPref]
    /// Convenience accessor for the Following timeline preferences.
    public var homeFeedView: FeedViewPref? { feedViews["home"] }
    /// `app.bsky.actor.defs#contentLanguagesPref.languages` — BCP-47 codes
    /// for the languages the user wants to see in their feeds. Empty array
    /// (or missing pref) means "show all languages". The Languages settings
    /// screen reads / writes this list as a multi-select.
    public let contentLanguages: [String]
    /// `app.bsky.actor.defs#postLanguagesPref.languages` — BCP-47 codes the
    /// composer pre-fills as the language(s) for new posts. RN treats the
    /// first entry as the "primary post language"; the Settings → Languages
    /// → Primary language picker writes that single code as a one-element
    /// array.
    public let postLanguages: [String]
    /// `app.bsky.actor.defs#mutedWordsPref.items` — the user's curated list
    /// of muted words and tags. Used by the Moderation → Muted Words & Tags
    /// screen and by feed-side filtering once wired (see #0132).
    public let mutedWords: [MutedWord]
    /// `app.bsky.actor.defs#labelersPref.labelers[].did` — DIDs of the
    /// labeler services the viewer has subscribed to. Mirrors RN's
    /// `preferences.moderationPrefs.labelers.map(l => l.did)`. The
    /// Moderation hub's "Subscribed labelers" advanced section reads this
    /// list, then feeds the DIDs into `app.bsky.labeler.getServices` to
    /// resolve display names + availability (see #0133).
    public let subscribedLabelerDIDs: [DID]

    private enum OuterKeys: String, CodingKey { case preferences }

    public init(from decoder: any Decoder) throws {
        struct FeedItemHelper: Decodable {
            let id: String
            let type: String
            let value: String
            let pinned: Bool
        }
        struct MutedWordHelper: Decodable {
            let id: String?
            let value: String
            let targets: [String]
            let actorTarget: String?
            let expiresAt: String?
        }
        struct LabelerEntryHelper: Decodable {
            let did: DID
        }
        struct Item: Decodable {
            let type: String
            let enabled: Bool?
            let label: String?
            let visibility: String?
            let labelerDid: DID?
            let feedItems: [FeedItemHelper]?
            let mutedWordItems: [MutedWordHelper]?
            let labelerEntries: [LabelerEntryHelper]?
            let birthDate: String?
            let sort: String?
            let prioritizeFollowedUsers: Bool?
            // feedViewPref fields
            let feed: String?
            let hideReplies: Bool?
            let hideRepliesByUnfollowed: Bool?
            let hideRepliesByLikeCount: Int?
            let hideReposts: Bool?
            let hideQuotePosts: Bool?
            // contentLanguagesPref / postLanguagesPref share `languages: [String]`
            let languages: [String]?
            private enum CodingKeys: String, CodingKey {
                case type = "$type", enabled, label, visibility, labelerDid, birthDate
                case items
                case labelers
                case sort, prioritizeFollowedUsers
                case feed, hideReplies, hideRepliesByUnfollowed, hideRepliesByLikeCount,
                     hideReposts, hideQuotePosts
                case languages
            }

            init(from decoder: any Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                self.type = try c.decode(String.self, forKey: .type)
                self.enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled)
                self.label = try c.decodeIfPresent(String.self, forKey: .label)
                self.visibility = try c.decodeIfPresent(String.self, forKey: .visibility)
                self.labelerDid = try c.decodeIfPresent(DID.self, forKey: .labelerDid)
                self.birthDate = try c.decodeIfPresent(String.self, forKey: .birthDate)
                self.sort = try c.decodeIfPresent(String.self, forKey: .sort)
                self.prioritizeFollowedUsers = try c.decodeIfPresent(Bool.self, forKey: .prioritizeFollowedUsers)
                self.feed = try c.decodeIfPresent(String.self, forKey: .feed)
                self.hideReplies = try c.decodeIfPresent(Bool.self, forKey: .hideReplies)
                self.hideRepliesByUnfollowed = try c.decodeIfPresent(Bool.self, forKey: .hideRepliesByUnfollowed)
                self.hideRepliesByLikeCount = try c.decodeIfPresent(Int.self, forKey: .hideRepliesByLikeCount)
                self.hideReposts = try c.decodeIfPresent(Bool.self, forKey: .hideReposts)
                self.hideQuotePosts = try c.decodeIfPresent(Bool.self, forKey: .hideQuotePosts)
                self.languages = try c.decodeIfPresent([String].self, forKey: .languages)
                // `items` is shared between savedFeedsPrefV2 (FeedItemHelper)
                // and mutedWordsPref (MutedWordHelper). Pick decoder by `$type`.
                if type == "app.bsky.actor.defs#mutedWordsPref" {
                    self.feedItems = nil
                    self.mutedWordItems = try c.decodeIfPresent([MutedWordHelper].self, forKey: .items)
                } else if type == "app.bsky.actor.defs#savedFeedsPrefV2" {
                    self.feedItems = try c.decodeIfPresent([FeedItemHelper].self, forKey: .items)
                    self.mutedWordItems = nil
                } else {
                    self.feedItems = nil
                    self.mutedWordItems = nil
                }
                // `labelersPref.labelers` is its own array; pull only when the
                // `$type` matches so we don't accidentally trip on unrelated
                // preference shapes.
                if type == "app.bsky.actor.defs#labelersPref" {
                    self.labelerEntries = try c.decodeIfPresent([LabelerEntryHelper].self, forKey: .labelers)
                } else {
                    self.labelerEntries = nil
                }
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

        // `feedViewPref` is keyed by `feed`; multiple instances may coexist.
        // Build a dictionary so callers can pluck `home` (Following timeline)
        // or any saved-feed key in O(1).
        var feedViews: [String: FeedViewPref] = [:]
        for item in items where item.type == "app.bsky.actor.defs#feedViewPref" {
            guard let feed = item.feed else { continue }
            feedViews[feed] = FeedViewPref(
                feed: feed,
                hideReplies: item.hideReplies ?? FeedViewPref.defaultHome.hideReplies,
                hideRepliesByUnfollowed: item.hideRepliesByUnfollowed
                    ?? FeedViewPref.defaultHome.hideRepliesByUnfollowed,
                hideRepliesByLikeCount: item.hideRepliesByLikeCount
                    ?? FeedViewPref.defaultHome.hideRepliesByLikeCount,
                hideReposts: item.hideReposts ?? FeedViewPref.defaultHome.hideReposts,
                hideQuotePosts: item.hideQuotePosts ?? FeedViewPref.defaultHome.hideQuotePosts
            )
        }
        self.feedViews = feedViews

        self.contentLanguages = items
            .first { $0.type == "app.bsky.actor.defs#contentLanguagesPref" }?
            .languages
            ?? []

        self.postLanguages = items
            .first { $0.type == "app.bsky.actor.defs#postLanguagesPref" }?
            .languages
            ?? []

        let isoFractional: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f
        }()
        self.mutedWords = items
            .first { $0.type == "app.bsky.actor.defs#mutedWordsPref" }?
            .mutedWordItems?
            .map { helper in
                let expires: Date?
                if let raw = helper.expiresAt {
                    expires = isoFractional.date(from: raw) ?? parser.date(from: raw)
                } else {
                    expires = nil
                }
                return MutedWord(
                    id: helper.id,
                    value: helper.value,
                    targets: helper.targets,
                    actorTarget: helper.actorTarget,
                    expiresAt: expires
                )
            }
            ?? []

        self.subscribedLabelerDIDs = items
            .first { $0.type == "app.bsky.actor.defs#labelersPref" }?
            .labelerEntries?
            .map { $0.did }
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

    /// Writes a single `feedViewPref` carrying the supplied flags. Mirrors
    /// RN's `agent.setFeedViewPrefs('home', prefs)` path used by
    /// `useSetFeedViewPreferencesMutation`. The lexicon keys these prefs by
    /// `feed`, so multiple per-feed entries can coexist on the server; this
    /// initializer puts only the one being edited.
    public init(feedView: FeedViewPref) {
        self.preferences = [AnyEncodable(_FeedViewPref(feedView))]
    }

    private struct _FeedViewPref: Encodable, Sendable {
        let pref: FeedViewPref
        private enum K: String, CodingKey {
            case type = "$type"
            case feed
            case hideReplies
            case hideRepliesByUnfollowed
            case hideRepliesByLikeCount
            case hideReposts
            case hideQuotePosts
        }
        init(_ pref: FeedViewPref) { self.pref = pref }
        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: K.self)
            try c.encode("app.bsky.actor.defs#feedViewPref", forKey: .type)
            try c.encode(pref.feed, forKey: .feed)
            try c.encode(pref.hideReplies, forKey: .hideReplies)
            try c.encode(pref.hideRepliesByUnfollowed, forKey: .hideRepliesByUnfollowed)
            try c.encode(pref.hideRepliesByLikeCount, forKey: .hideRepliesByLikeCount)
            try c.encode(pref.hideReposts, forKey: .hideReposts)
            try c.encode(pref.hideQuotePosts, forKey: .hideQuotePosts)
        }
    }

    /// Writes a `contentLanguagesPref` carrying the user's selected feed
    /// languages (BCP-47 codes). Empty array means "show all languages",
    /// matching RN's `useLanguagePrefsApi.setContentLanguages` semantics.
    public init(contentLanguages: [String]) {
        self.preferences = [AnyEncodable(_LanguagesPref(
            type: "app.bsky.actor.defs#contentLanguagesPref",
            languages: contentLanguages
        ))]
    }

    /// Writes a `postLanguagesPref` carrying the user's preferred composer
    /// languages (BCP-47 codes). The Settings → Languages → Primary language
    /// picker passes a single code as a one-element array; this matches RN's
    /// `useLanguagePrefsApi.setPrimaryLanguage` which writes a one-element
    /// array via `agent.setPostLanguagesPref`.
    public init(postLanguages: [String]) {
        self.preferences = [AnyEncodable(_LanguagesPref(
            type: "app.bsky.actor.defs#postLanguagesPref",
            languages: postLanguages
        ))]
    }

    private struct _LanguagesPref: Encodable, Sendable {
        let type: String
        let languages: [String]
        private enum K: String, CodingKey { case type = "$type", languages }
        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: K.self)
            try c.encode(type, forKey: .type)
            try c.encode(languages, forKey: .languages)
        }
    }

    /// Writes a `mutedWordsPref` carrying the supplied list of muted-word
    /// entries. Mirrors RN's `agent.upsertMutedWords / removeMutedWord`
    /// pattern: those helpers ultimately re-write the entire `items` array,
    /// so the SwiftUI client does the same thing — load, mutate locally,
    /// write the whole list back.
    public init(mutedWords: [MutedWord]) {
        self.preferences = [AnyEncodable(_MutedWordsPref(items: mutedWords))]
    }

    /// Writes a `labelersPref` carrying the supplied list of subscribed
    /// labeler DIDs. Mirrors RN's `useRemoveLabelersMutation` /
    /// `agent.removeLabeler` cleanup path: those helpers re-write the
    /// entire `labelers` array, so the SwiftUI client does the same — load,
    /// drop the unavailable entries, write the trimmed list back.
    public init(subscribedLabelerDIDs: [DID]) {
        self.preferences = [AnyEncodable(_LabelersPref(dids: subscribedLabelerDIDs))]
    }

    private struct _LabelersPref: Encodable, Sendable {
        let dids: [DID]
        private enum K: String, CodingKey { case type = "$type", labelers }
        private struct Entry: Encodable, Sendable {
            let did: DID
        }
        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: K.self)
            try c.encode("app.bsky.actor.defs#labelersPref", forKey: .type)
            try c.encode(dids.map { Entry(did: $0) }, forKey: .labelers)
        }
    }

    private struct _MutedWordsPref: Encodable, Sendable {
        let items: [MutedWord]
        private enum K: String, CodingKey { case type = "$type", items }
        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: K.self)
            try c.encode("app.bsky.actor.defs#mutedWordsPref", forKey: .type)
            try c.encode(items.map { _MutedWordItem($0) }, forKey: .items)
        }
    }

    /// Per-entry encoder. Emits ISO-8601 `expiresAt` and omits `nil` fields
    /// so the appview keeps clients that don't carry them happy.
    private struct _MutedWordItem: Encodable, Sendable {
        let word: MutedWord
        init(_ word: MutedWord) { self.word = word }
        private enum K: String, CodingKey { case id, value, targets, actorTarget, expiresAt }
        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: K.self)
            try c.encodeIfPresent(word.id, forKey: .id)
            try c.encode(word.value, forKey: .value)
            try c.encode(word.targets, forKey: .targets)
            try c.encodeIfPresent(word.actorTarget, forKey: .actorTarget)
            if let expiresAt = word.expiresAt {
                let fmt = ISO8601DateFormatter()
                try c.encode(fmt.string(from: expiresAt), forKey: .expiresAt)
            }
        }
    }
}

// MARK: - app.bsky.labeler.getServices response

public struct GetLabelerServicesResponse: Decodable, Sendable {
    public let views: [LabelerView]
}

// MARK: - app.bsky.labeler.defs#labelerView

/// A labeler service view returned by `app.bsky.labeler.getServices`.
///
/// `subjectTypes`, `subjectCollections`, and `reasonTypes` are present when
/// the lexicon returns the *detailed* view (`detailed=true` query parameter)
/// or whenever the labeler service record declares them. They drive which
/// subjects (account, chat, record) and which Ozone reason types a given
/// labeler is willing to accept reports about — the Report dialog filters
/// the list of candidate labelers using these fields. Mirrors the matching
/// branch in RN's `ReportDialog/index.tsx#supportedLabelers`.
public struct LabelerView: Codable, Sendable {
    public let uri: ATURI
    public let cid: CID
    public let creator: ProfileView
    public let likeCount: Int?
    public let labels: [Label]
    public let indexedAt: Date
    /// Subject types this labeler accepts (`"account"`, `"chat"`, `"record"`).
    /// `nil` means "no restriction", per RN's filter rule.
    public let subjectTypes: [String]?
    /// NSIDs of record collections this labeler accepts (e.g.
    /// `"app.bsky.feed.post"`). `nil` means "all collections".
    public let subjectCollections: [String]?
    /// Reason-type strings this labeler will accept (`com.atproto.moderation.defs#reason*`
    /// or the newer Ozone variants). `nil` means "all reason types".
    public let reasonTypes: [String]?

    public init(
        uri: ATURI,
        cid: CID,
        creator: ProfileView,
        likeCount: Int?,
        labels: [Label] = [],
        indexedAt: Date,
        subjectTypes: [String]? = nil,
        subjectCollections: [String]? = nil,
        reasonTypes: [String]? = nil
    ) {
        self.uri = uri
        self.cid = cid
        self.creator = creator
        self.likeCount = likeCount
        self.labels = labels
        self.indexedAt = indexedAt
        self.subjectTypes = subjectTypes
        self.subjectCollections = subjectCollections
        self.reasonTypes = reasonTypes
    }
}
