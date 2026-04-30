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
    /// All actors involved, deduplicated, ordered from most recent to oldest.
    public let actors: [ProfileBasic]
    /// `true` if any constituent notification is unread.
    public let isRead: Bool
    /// Timestamp of the most recent notification in the group.
    public let indexedAt: Date

    /// `true` when only one actor is in the group.
    public var isSingle: Bool { actors.count == 1 }
}

// MARK: - NotificationsViewModel

@Observable
public final class NotificationsViewModel {

    public var notifications: [NotificationView] { store.notifications }
    public var isLoading: Bool { store.isLoading }
    public var errorMessage: String? { store.errorMessage }
    public var unreadCount: Int { store.unreadCount }

    // MARK: Grouped notifications

    /// Notifications collapsed by `(reason, reasonSubject)`.
    ///
    /// For `"follow"` notifications — which have no `reasonSubject` — each actor gets its
    /// own group keyed by their DID so follows are never merged across different actors.
    public var groupedNotifications: [GroupedNotification] {
        var order: [String] = []
        var buckets: [String: (reason: String, subject: ATURI?, actors: [ProfileBasic], anyUnread: Bool, latest: Date)] = [:]

        for n in store.notifications {
            // Follow notifications have no reasonSubject; key by actor DID so they stay separate.
            let key: String
            if n.reason == "follow" {
                key = "follow:\(n.author.did.rawValue)"
            } else {
                key = "\(n.reason):\(n.reasonSubject?.rawValue ?? n.author.did.rawValue)"
            }

            if buckets[key] == nil {
                order.append(key)
                buckets[key] = (n.reason, n.reasonSubject, [], false, n.indexedAt)
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
                actors: b.actors,
                isRead: !b.anyUnread,
                indexedAt: b.latest
            )
        }
    }

    private let store: any NotificationsStoring

    public init(network: any NetworkClient) {
        self.store = NotificationsStore(network: network)
    }

    public func loadInitial() async { await store.loadInitial() }
    public func loadMore() async { await store.loadMore() }
    public func refresh() async { await store.refresh() }
    public func markSeen() async { await store.markSeen() }
    public func fetchUnreadCount() async { await store.fetchUnreadCount() }
}
