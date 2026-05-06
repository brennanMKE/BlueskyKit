import Foundation
import Observation
import BlueskyCore
import BlueskyKit

// MARK: - GroupedNotification

/// A collapsed view of one or more notifications sharing the same reason and subject.
///
/// Multiple actors performing the same action on the same post (e.g. several people
/// liking the same post) are merged into a single `GroupedNotification` so the UI
/// can render "Alice, Bob, and 3 others liked your post" instead of individual rows.
public struct GroupedNotification: Identifiable, Sendable {
    /// Stable identifier composed of `reason` + the subject URI (or actor DID for follows).
    public let id: String
    /// Notification kind: `"like"`, `"repost"`, `"follow"`, `"mention"`, `"reply"`, `"quote"`.
    public let reason: String
    /// AT-URI of the post being acted on (nil for follows).
    public let reasonSubject: ATURI?
    /// AT-URI of the post whose body should be previewed inline on the row,
    /// or `nil` if this reason has no associated post (`follow`, `verified`,
    /// etc.). For `reply`/`mention`/`quote` this is the notification's own
    /// `uri` (the actor's new post); for `like`/`repost`/etc. it's the
    /// `reasonSubject` (the viewer's own post that was liked/reposted).
    public let previewPostURI: ATURI?
    /// All actors involved, deduplicated, ordered from most recent to oldest.
    public let actors: [ProfileBasic]
    /// `true` if any constituent notification is unread.
    public let isRead: Bool
    /// Timestamp of the most recent notification in the group.
    public let indexedAt: Date

    /// `true` when only one actor is in the group.
    public var isSingle: Bool { actors.count == 1 }

    public init(
        id: String,
        reason: String,
        reasonSubject: ATURI?,
        previewPostURI: ATURI?,
        actors: [ProfileBasic],
        isRead: Bool,
        indexedAt: Date
    ) {
        self.id = id
        self.reason = reason
        self.reasonSubject = reasonSubject
        self.previewPostURI = previewPostURI
        self.actors = actors
        self.isRead = isRead
        self.indexedAt = indexedAt
    }
}

/// Reason values for which we should fetch and render an inline post-text
/// preview on the notification row (#0079).
///
/// `reply`/`mention`/`quote` preview the actor's new post (notification's
/// own `uri`); `like`/`repost`/`subscribed-post`/`like-via-repost`/
/// `repost-via-repost` preview the viewer's original post (`reasonSubject`).
private let postPreviewReasons: Set<String> = [
    "reply", "mention", "quote",
    "like", "repost",
    "subscribed-post",
    "like-via-repost", "repost-via-repost"
]

/// Reasons whose preview source is the notification's own `uri` (the actor's
/// new post). All other post-preview reasons fall back to `reasonSubject`.
private let actorPostReasons: Set<String> = ["reply", "mention", "quote"]

// MARK: - NotificationsViewModel

@Observable
public final class NotificationsViewModel {

    public var notifications: [NotificationView] { store.notifications }
    public var isLoading: Bool { store.isLoading }
    public var errorMessage: String? { store.errorMessage }
    public var unreadCount: Int { store.unreadCount }

    /// Active filter — drives which slice of notifications is presented.
    /// Defaults to `.all` on cold-start; UI may flip to `.mentions` for the
    /// Mentions tab. Persisted only within the session — not across launches.
    public var filter: NotificationFilter {
        get { store.filter }
        set { store.setFilter(newValue) }
    }

    // MARK: Grouped notifications

    /// Notifications collapsed by `(reason, reasonSubject)`, scoped to the
    /// active filter — only entries whose `reason` is included by
    /// `store.filter.keepReasons` participate.
    ///
    /// For `"follow"` notifications — which have no `reasonSubject` — each actor gets its
    /// own group keyed by their DID so follows are never merged across different actors.
    public var groupedNotifications: [GroupedNotification] {
        var order: [String] = []
        var buckets: [String: (
            reason: String,
            subject: ATURI?,
            previewURI: ATURI?,
            actors: [ProfileBasic],
            anyUnread: Bool,
            latest: Date
        )] = [:]

        for n in store.notifications {
            // Reply/mention/quote rows preview the actor's new post — each
            // has unique body text — so they MUST stay ungrouped (key by
            // notification URI). Follow notifications have no reasonSubject;
            // key by actor DID so they stay separate. Like/repost/etc.
            // continue to group by `(reason, reasonSubject)`.
            let key: String
            if n.reason == "follow" {
                key = "follow:\(n.author.did.rawValue)"
            } else if actorPostReasons.contains(n.reason) {
                key = "\(n.reason):\(n.uri.rawValue)"
            } else {
                key = "\(n.reason):\(n.reasonSubject?.rawValue ?? n.author.did.rawValue)"
            }

            // The post URI we want to preview on this row.
            let previewURI: ATURI?
            if actorPostReasons.contains(n.reason) {
                previewURI = n.uri
            } else if postPreviewReasons.contains(n.reason) {
                previewURI = n.reasonSubject
            } else {
                previewURI = nil
            }

            if buckets[key] == nil {
                order.append(key)
                buckets[key] = (n.reason, n.reasonSubject, previewURI, [], false, n.indexedAt)
            }

            var bucket = buckets[key]!
            // Deduplicate actors by DID.
            if !bucket.actors.contains(where: { $0.did == n.author.did }) {
                bucket.actors.append(n.author)
            }
            if !n.isRead { bucket.anyUnread = true }
            if n.indexedAt > bucket.latest { bucket.latest = n.indexedAt }
            buckets[key] = bucket
        }

        return order.compactMap { key -> GroupedNotification? in
            guard let b = buckets[key] else { return nil }
            return GroupedNotification(
                id: key,
                reason: b.reason,
                reasonSubject: b.subject,
                previewPostURI: b.previewURI,
                actors: b.actors,
                isRead: !b.anyUnread,
                indexedAt: b.latest
            )
        }
    }

    // MARK: - Post hydration

    /// AT-URIs of the posts that should be hydrated for inline previews on
    /// the current notification list. Drains both the actor-post URIs
    /// (replies/mentions/quotes) and the subject URIs (likes/reposts/etc.)
    /// across `store.notifications` (unfiltered, so the cache is shared
    /// across All / Mentions tabs).
    public var postPreviewURIs: [ATURI] {
        var seen = Set<String>()
        var result: [ATURI] = []
        for n in store.allNotifications {
            let uri: ATURI?
            if actorPostReasons.contains(n.reason) {
                uri = n.uri
            } else if postPreviewReasons.contains(n.reason) {
                uri = n.reasonSubject
            } else {
                uri = nil
            }
            if let uri, seen.insert(uri.rawValue).inserted {
                result.append(uri)
            }
        }
        return result
    }

    private let store: any NotificationsStoring

    /// Cache of resolved `PostView` records used to render inline post-text
    /// previews on each notification row (#0079). Exposed publicly so the
    /// screen can read `posts(for:)` and `isLoading(uri:)` per row.
    public let postCache: NotificationPostCache

    public init(network: any NetworkClient) {
        self.store = NotificationsStore(network: network)
        self.postCache = NotificationPostCache(network: network)
    }

    public func loadInitial() async {
        await store.loadInitial()
        await hydratePreviewPosts()
    }

    public func loadMore() async {
        await store.loadMore()
        await hydratePreviewPosts()
    }

    public func refresh() async {
        await store.refresh()
        await hydratePreviewPosts()
    }

    public func markSeen() async { await store.markSeen() }
    public func fetchUnreadCount() async { await store.fetchUnreadCount() }

    public func setFilter(_ filter: NotificationFilter) {
        store.setFilter(filter)
    }

    /// Kicks off `getPosts` fan-out for any newly-seen preview URIs. The
    /// cache itself dedupes against already-resolved / in-flight URIs so
    /// re-running this after `loadMore` is cheap.
    private func hydratePreviewPosts() async {
        await postCache.hydrate(uris: postPreviewURIs)
    }
}
