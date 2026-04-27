import Foundation
import Observation
import BlueskyCore
import BlueskyKit

@Observable
public final class ListsViewModel {

    public var lists: [ListView] { store.lists }
    public var isLoading: Bool { store.isLoading }
    public var error: String? { store.error }

    private let store: any ListsStoring
    private let accountStore: any AccountStore

    public init(network: any NetworkClient, accountStore: any AccountStore) {
        self.store = ListsStore(network: network, accountStore: accountStore)
        self.accountStore = accountStore
    }

    func currentDID() async throws -> String? {
        try await accountStore.loadCurrentDID()?.rawValue
    }

    public func loadLists(actorDID: String) async { await store.loadLists(actorDID: actorDID) }
    public func loadMore(actorDID: String) async { await store.loadMore(actorDID: actorDID) }
    public func createList(name: String, description: String?, purpose: String = "app.bsky.graph.defs#curatelist") async {
        await store.createList(name: name, description: description, purpose: purpose)
    }
    public func deleteList(uri: ATURI) async { await store.deleteList(uri: uri) }
    public func addMember(listURI: ATURI, subjectDID: DID, repo: String) async {
        await store.addMember(listURI: listURI, subjectDID: subjectDID, repo: repo)
    }
    public func removeMember(itemURI: ATURI, repo: String) async {
        await store.removeMember(itemURI: itemURI, repo: repo)
    }
    public func createStarterPack(name: String, description: String?, listURI: ATURI) async {
        await store.createStarterPack(name: name, description: description, listURI: listURI)
    }

    public func clearError() { store.clearError() }
}
