import Foundation
import Observation
import BlueskyCore
import BlueskyKit

@Observable
public final class NotificationsViewModel {

    public var notifications: [NotificationView] { store.notifications }
    public var isLoading: Bool { store.isLoading }
    public var errorMessage: String? { store.errorMessage }
    public var unreadCount: Int { store.unreadCount }

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
