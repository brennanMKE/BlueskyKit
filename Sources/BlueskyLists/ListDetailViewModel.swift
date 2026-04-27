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

    init(network: any NetworkClient) {
        self.store = ListDetailStore(network: network)
    }

    func load(listURI: ATURI) async { await store.load(listURI: listURI) }
    func loadMore() async { await store.loadMore() }
    func loadFeed() async { await store.loadFeed() }
    func loadMoreFeed() async { await store.loadMoreFeed() }
}
