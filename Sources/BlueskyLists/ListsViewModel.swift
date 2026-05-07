import Foundation
import Observation
import BlueskyCore
import BlueskyKit

@Observable
public final class ListsViewModel {

    public var lists: [ListView] { store.lists }
    public var isLoading: Bool { store.isLoading }
    public var error: String? { store.error }

    /// Resolved on first `loadLists` so the computed split arrays don't have
    /// to hop the actor every read. Stays `nil` when logged out, in which
    /// case `ownedLists` returns everything (matches the existing flat view).
    public private(set) var viewerDID: DID?

    /// Lists the signed-in viewer authored. Mirrors RN's `useMyListsQuery`
    /// with `filter: 'curate'`, which only fetches `getLists({actor: viewerDID})`.
    public var ownedLists: [ListView] {
        guard let viewerDID else { return store.lists }
        return store.lists.filter { $0.creator.did == viewerDID }
    }

    /// Lists the viewer is subscribed to without owning. RN's curate hub
    /// (`MyLists filter="curate"`) does not surface subscribed curate lists —
    /// those flow through `getListMutes`/`getListBlocks` only for the `mod`
    /// filter (which has its own screen). Kept here so the section header
    /// renders alongside "My Lists" for symmetry with mod lists; when empty
    /// the screen shows the placeholder copy.
    public var subscribedLists: [ListView] {
        guard let viewerDID else { return [] }
        return store.lists.filter { $0.creator.did != viewerDID }
    }

    private let store: any ListsStoring
    private let accountStore: any AccountStore

    public init(network: any NetworkClient, accountStore: any AccountStore) {
        self.store = ListsStore(network: network, accountStore: accountStore)
        self.accountStore = accountStore
    }

    func currentDID() async throws -> String? {
        try await accountStore.loadCurrentDID()?.rawValue
    }

    /// Resolves the signed-in viewer DID and caches it on the view model.
    /// The lists hub uses this to split owned vs subscribed lists. Failures
    /// leave `viewerDID == nil`, which is the same as the logged-out path.
    public func resolveViewerDID() async {
        if viewerDID == nil {
            viewerDID = try? await accountStore.loadCurrentDID()
        }
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

    /// Wizard create path. See `ListsStore.createStarterPackWithProfiles` —
    /// builds the backing reference list, fans out the curated members via
    /// `applyWrites`, then creates the starter-pack record. Returns `true`
    /// on success.
    public func createStarterPackWithProfiles(
        name: String,
        description: String?,
        profileDIDs: [DID],
        feedURIs: [ATURI]
    ) async -> Bool {
        await store.createStarterPackWithProfiles(
            name: name,
            description: description,
            profileDIDs: profileDIDs,
            feedURIs: feedURIs
        )
    }

    public func clearError() { store.clearError() }
}
