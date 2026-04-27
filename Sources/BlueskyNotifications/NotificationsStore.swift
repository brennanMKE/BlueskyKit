import Foundation
import OSLog
import Observation
import BlueskyCore
import BlueskyKit

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "co.sstools.Bluesky", category: "NotificationsStore")

// MARK: - NotificationsStoring

public protocol NotificationsStoring: AnyObject, Observable, Sendable {
    var notifications: [NotificationView] { get }
    var isLoading: Bool { get }
    var errorMessage: String? { get }
    var unreadCount: Int { get }

    func loadInitial() async
    func loadMore() async
    func refresh() async
    func markSeen() async
    func fetchUnreadCount() async
}

// MARK: - NotificationsStore

@Observable
public final class NotificationsStore: NotificationsStoring {

    public private(set) var notifications: [NotificationView] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public private(set) var unreadCount: Int = 0

    private var cursor: String?

    private let network: any NetworkClient

    public init(network: any NetworkClient) {
        self.network = network
    }

    public func loadInitial() async {
        guard !isLoading, notifications.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            let resp: ListNotificationsResponse = try await network.get(
                lexicon: "app.bsky.notification.listNotifications",
                params: ["limit": "50"]
            )
            notifications = resp.notifications
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
            notifications.append(contentsOf: resp.notifications)
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
            notifications = resp.notifications
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
            unreadCount = 0
        } catch {}
    }

    public func fetchUnreadCount() async {
        do {
            let resp: GetUnreadCountResponse = try await network.get(
                lexicon: "app.bsky.notification.getUnreadCount",
                params: [:]
            )
            unreadCount = resp.count
        } catch {}
    }
}
