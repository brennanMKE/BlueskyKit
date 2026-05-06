import Foundation
import OSLog
import Observation
import BlueskyCore
import BlueskyKit

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "co.sstools.Bluesky", category: "NotificationsStore")

// MARK: - NotificationFilter

/// Which slice of the notifications feed the store is presenting.
///
/// `.all` returns every reason from `app.bsky.notification.listNotifications`.
/// `.mentions` keeps only `mention`, `reply`, and `quote` reasons — the
/// directed-at-the-viewer subset matching the React Native reference
/// (`feed.ts` → `reasons = ['mention', 'reply', 'quote']`).
public enum NotificationFilter: String, CaseIterable, Sendable, Hashable {
    case all
    case mentions

    /// Reason values kept when this filter is active. Empty means "no filter".
    public var keepReasons: Set<String> {
        switch self {
        case .all:      return []
        case .mentions: return ["mention", "reply", "quote"]
        }
    }

    public func includes(_ reason: String) -> Bool {
        let kept = keepReasons
        return kept.isEmpty || kept.contains(reason)
    }
}

// MARK: - NotificationsStoring

public protocol NotificationsStoring: AnyObject, Observable, Sendable {
    /// All notifications fetched so far, regardless of active filter. Used by
    /// the view model to derive `groupedNotifications` per filter and to keep
    /// the unread badge bound to the All count.
    var allNotifications: [NotificationView] { get }
    /// Notifications visible under the active filter — `allNotifications`
    /// filtered by `filter.keepReasons`.
    var notifications: [NotificationView] { get }
    var isLoading: Bool { get }
    var errorMessage: String? { get }
    var unreadCount: Int { get }
    var filter: NotificationFilter { get }

    func setFilter(_ filter: NotificationFilter)
    func loadInitial() async
    func loadMore() async
    func refresh() async
    func markSeen() async
    func fetchUnreadCount() async
}

// MARK: - NotificationsStore

@Observable
public final class NotificationsStore: NotificationsStoring {

    public private(set) var allNotifications: [NotificationView] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public private(set) var unreadCount: Int = 0
    public private(set) var filter: NotificationFilter = .all

    /// Notifications visible under the active filter.
    ///
    /// Filtering is client-side: AT Proto's `listNotifications` lexicon does
    /// expose a server-side `reasons` array parameter, but our shared
    /// `NetworkClient.get(_:params:)` signature is a flat `[String: String]`
    /// dictionary that can't carry repeated query items. Filtering locally
    /// keeps the network layer untouched and lets the cached All page back
    /// the Mentions tab without a separate fetch — see "Gotchas" in #0078.
    public var notifications: [NotificationView] {
        let kept = filter.keepReasons
        if kept.isEmpty { return allNotifications }
        return allNotifications.filter { kept.contains($0.reason) }
    }

    private var cursor: String?

    private let network: any NetworkClient

    public init(network: any NetworkClient) {
        self.network = network
    }

    /// Switch the active filter slice. The underlying data is shared across
    /// filters so flipping is instantaneous and never refetches.
    public func setFilter(_ filter: NotificationFilter) {
        self.filter = filter
    }

    public func loadInitial() async {
        guard !isLoading, allNotifications.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            let resp: ListNotificationsResponse = try await network.get(
                lexicon: "app.bsky.notification.listNotifications",
                params: ["limit": "50"]
            )
            allNotifications = resp.notifications
            cursor = resp.cursor
        } catch {
            logger.error("notifications fetch error: \(error, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func loadMore() async {
        guard !isLoading, let cursor else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let resp: ListNotificationsResponse = try await network.get(
                lexicon: "app.bsky.notification.listNotifications",
                params: ["limit": "50", "cursor": cursor]
            )
            allNotifications.append(contentsOf: resp.notifications)
            self.cursor = resp.cursor
        } catch {}
    }

    public func refresh() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            let resp: ListNotificationsResponse = try await network.get(
                lexicon: "app.bsky.notification.listNotifications",
                params: ["limit": "50"]
            )
            allNotifications = resp.notifications
            cursor = resp.cursor
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func markSeen() async {
        do {
            let _: EmptyResponse = try await network.post(
                lexicon: "app.bsky.notification.updateSeen",
                body: UpdateSeenRequest()
            )
            // The badge is bound to the All-count regardless of active
            // filter — `markSeen` zeroes it server-side, mirror locally.
            unreadCount = 0
        } catch {}
    }

    public func fetchUnreadCount() async {
        do {
            // No filter — the unread badge always reflects total unread,
            // even when the user is currently viewing the Mentions tab.
            let resp: GetUnreadCountResponse = try await network.get(
                lexicon: "app.bsky.notification.getUnreadCount",
                params: [:]
            )
            unreadCount = resp.count
        } catch {}
    }
}
