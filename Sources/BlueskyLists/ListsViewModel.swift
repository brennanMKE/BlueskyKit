import Foundation
import Observation
import BlueskyCore
import BlueskyKit

@Observable
public final class ListsViewModel {

    // MARK: - State

    public var lists: [ListView] = []
    public var cursor: Cursor?
    public var isLoading = false
    public var error: String?

    // MARK: - Dependencies

    private let network: any NetworkClient
    private let accountStore: any AccountStore

    public init(network: any NetworkClient, accountStore: any AccountStore) {
        self.network = network
        self.accountStore = accountStore
    }

    // MARK: - DID helper

    /// Returns the rawValue of the current account's DID, or nil if unavailable.
    func currentDID() async throws -> String? {
        return try await accountStore.loadCurrentDID()?.rawValue
    }

    // MARK: - Load lists

    public func loadLists(actorDID: String) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        error = nil
        do {
            let resp: GetListsResponse = try await network.get(
                lexicon: "app.bsky.graph.getLists",
                params: ["actor": actorDID, "limit": "50"]
            )
            lists = resp.lists
            cursor = resp.cursor
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func loadMore(actorDID: String) async {
        guard let cursor else { return }
        do {
            let resp: GetListsResponse = try await network.get(
                lexicon: "app.bsky.graph.getLists",
                params: ["actor": actorDID, "limit": "50", "cursor": cursor]
            )
            lists.append(contentsOf: resp.lists)
            self.cursor = resp.cursor
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Create list

    public func createList(
        name: String,
        description: String?,
        purpose: String = "app.bsky.graph.defs#curatelist"
    ) async {
        guard let viewerDID = try? await accountStore.loadCurrentDID() else { return }
        do {
            let record = ListRecord(name: name, description: description, purpose: purpose)
            let req = CreateRecordRequest(
                repo: viewerDID.rawValue,
                collection: "app.bsky.graph.list",
                record: record
            )
            let resp: CreateRecordResponse = try await network.post(
                lexicon: "com.atproto.repo.createRecord",
                body: req
            )
            // Reload to pick up the new list from the server
            _ = resp
            await loadLists(actorDID: viewerDID.rawValue)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Delete list

    public func deleteList(uri: ATURI) async {
        guard let rkey = uri.rkey,
              let viewerDID = try? await accountStore.loadCurrentDID() else { return }
        lists.removeAll { $0.uri == uri }
        do {
            let req = DeleteRecordRequest(
                repo: viewerDID.rawValue,
                collection: "app.bsky.graph.list",
                rkey: rkey
            )
            let _: EmptyResponse = try await network.post(
                lexicon: "com.atproto.repo.deleteRecord",
                body: req
            )
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Add member

    public func addMember(listURI: ATURI, subjectDID: DID, repo: String) async {
        do {
            let record = ListItemRecord(list: listURI, subject: subjectDID)
            let req = CreateRecordRequest(
                repo: repo,
                collection: "app.bsky.graph.listitem",
                record: record
            )
            let _: CreateRecordResponse = try await network.post(
                lexicon: "com.atproto.repo.createRecord",
                body: req
            )
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Remove member

    public func removeMember(itemURI: ATURI, repo: String) async {
        guard let rkey = itemURI.rkey else { return }
        do {
            let req = DeleteRecordRequest(
                repo: repo,
                collection: "app.bsky.graph.listitem",
                rkey: rkey
            )
            let _: EmptyResponse = try await network.post(
                lexicon: "com.atproto.repo.deleteRecord",
                body: req
            )
        } catch {
            self.error = error.localizedDescription
        }
    }
}
