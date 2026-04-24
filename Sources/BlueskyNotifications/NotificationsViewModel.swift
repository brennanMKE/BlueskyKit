import Foundation
import Observation
import BlueskyCore
import BlueskyKit

@Observable
public final class NotificationsViewModel {

    public var notifications: [NotificationView] = []
    public var cursor: String?
    public var isLoading = false
    public var errorMessage: String?
    public var unreadCount: Int = 0

    private let network: any NetworkClient

    public init(network: any NetworkClient) {
        self.network = network
    }

    // MARK: - Load

    public func loadInitial() async {
        guard !isLoading else { return }
        guard notifications.isEmpty else { return }
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

    // MARK: - Mark as seen

    public func markSeen() async {
        do {
            let _: EmptyResponse = try await network.post(
                lexicon: "app.bsky.notification.updateSeen",
                body: UpdateSeenRequest()
            )
            unreadCount = 0
        } catch {}
    }

    // MARK: - Unread count (for badge)

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
