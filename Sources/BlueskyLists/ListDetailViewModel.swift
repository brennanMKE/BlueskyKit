import Foundation
import Observation
import BlueskyCore
import BlueskyKit

@Observable
final class ListDetailViewModel {

    var list: ListView? { store.list }
    var members: [ListItemView] { store.members }
    var feed: [FeedViewPost] { store.feed }
    var isLoading: Bool { store.isLoading }
    var error: String? { store.error }

    private let store: any ListDetailStoring

    init(network: any NetworkClient, accountStore: (any AccountStore)? = nil) {
        self.store = ListDetailStore(network: network, accountStore: accountStore)
    }

    func load(listURI: ATURI) async { await store.load(listURI: listURI) }
    func loadMore() async { await store.loadMore() }
    func loadFeed() async { await store.loadFeed() }
    func loadMoreFeed() async { await store.loadMoreFeed() }

    /// Subscribe to a moderation list as a mute (RN's `Subscribe → Mute accounts`).
    func subscribeMute() async { await store.muteList() }
    /// Unsubscribe a moderation-list mute.
    func unsubscribeMute() async { await store.unmuteList() }

    /// Edit the loaded list. Returns `true` on success.
    func editList(name: String, description: String?) async -> Bool {
        await store.editList(name: name, description: description)
    }

    /// Delete the loaded list. Returns `true` on success.
    func deleteList() async -> Bool {
        await store.deleteList()
    }
}
