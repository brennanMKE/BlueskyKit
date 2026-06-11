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

    var searchResults: [ProfileBasic] { store.searchResults }
    var isSearching: Bool { store.isSearching }

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

    // MARK: - Member management (#0204)

    /// Debounced actor typeahead backing the "Add people" sheet.
    func searchMembers(query: String) { store.searchMembers(query: query) }

    /// Adds `profile` to the loaded list. Returns `true` on success.
    func addMember(_ profile: ProfileBasic) async -> Bool {
        await store.addMember(profile)
    }

    /// Removes the membership record `itemURI`. Returns `true` on success.
    func removeMember(itemURI: ATURI) async -> Bool {
        await store.removeMember(itemURI: itemURI)
    }

    /// The `listitem` record URI for `did`'s membership in the loaded list,
    /// or `nil` when `did` is not a member. Drives the Add/Remove toggle in
    /// the "Add people" sheet (RN's `getMembership`).
    func membershipItemURI(for did: DID) -> ATURI? {
        members.first { $0.subject.did == did }?.uri
    }
}
