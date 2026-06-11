import Testing
import Foundation
import Synchronization
import BlueskyKit
import BlueskyCore
import BlueskyLists

// MARK: - Fixtures

private let viewerDID = DID(rawValue: "did:plc:viewer123")
private let newListURI = "at://did:plc:viewer123/app.bsky.graph.list/3abc0203rkey"

/// `com.atproto.repo.createRecord` response for the new list.
private let createRecordFixture = Data("""
{"uri": "\(newListURI)", "cid": "bafyreicreated0203"}
""".utf8)

/// Stale `app.bsky.graph.getLists` page — the AppView has not indexed the
/// just-created record yet (#0203's failing condition).
private let emptyListsFixture = Data("""
{"lists": []}
""".utf8)

/// `getLists` page where the AppView has caught up: it returns the indexed
/// copy of the created list (distinguishable from the optimistic insert by
/// `listItemCount` and the server-resolved display name).
private let indexedListsFixture = Data("""
{
  "lists": [
    {
      "uri": "\(newListURI)",
      "cid": "bafyreicreated0203",
      "creator": {"did": "did:plc:viewer123", "handle": "viewer.test"},
      "name": "UITest-0203 List",
      "purpose": "app.bsky.graph.defs#curatelist",
      "labels": [],
      "listItemCount": 7
    }
  ]
}
""".utf8)

private func makeStoredAccount() -> StoredAccount {
    StoredAccount(
        account: Account(
            did: viewerDID,
            handle: Handle(rawValue: "viewer.test"),
            displayName: "Viewer",
            avatarURL: nil,
            serviceEndpoint: URL(string: "https://bsky.social")!,
            email: nil,
            emailConfirmed: nil
        ),
        accessJwt: "access",
        refreshJwt: "refresh"
    )
}

// MARK: - Test doubles

private final class ListsMockAccountStore: AccountStore, @unchecked Sendable {
    private var store: [String: StoredAccount] = [:]
    private var currentDID: DID?

    func save(_ account: StoredAccount) async throws { store[account.account.did.rawValue] = account }
    func loadAll() async throws -> [StoredAccount] { Array(store.values) }
    func load(did: DID) async throws -> StoredAccount? { store[did.rawValue] }
    func remove(did: DID) async throws { store[did.rawValue] = nil }
    func setCurrentDID(_ did: DID?) async throws { currentDID = did }
    func loadCurrentDID() async throws -> DID? { currentDID }
}

private func makeAccountStore() async throws -> ListsMockAccountStore {
    let store = ListsMockAccountStore()
    try await store.save(makeStoredAccount())
    try await store.setCurrentDID(viewerDID)
    return store
}

/// `NetworkClient` that serves a queue of canned `getLists` pages (the last
/// page repeats once the queue drains) and fixed `createRecord` /
/// `deleteRecord` responses, recording every request.
private final class ListsScriptedClient: NetworkClient, Sendable {
    private let listsPages: Mutex<[Data]>
    private let posted = Mutex<[String]>([])
    private let getCount = Mutex<Int>(0)

    init(listsPages: [Data]) {
        self.listsPages = Mutex(listsPages)
    }

    var postedLexicons: [String] { posted.withLock { $0 } }
    var listsGetCount: Int { getCount.withLock { $0 } }

    nonisolated func get<Response: Decodable & Sendable>(
        lexicon: String, params: [String: String]
    ) async throws -> Response {
        guard lexicon == "app.bsky.graph.getLists" else {
            throw ATError.unknown("unexpected GET \(lexicon) in test")
        }
        getCount.withLock { $0 += 1 }
        let page = listsPages.withLock { pages -> Data in
            guard let first = pages.first else {
                return emptyListsFixture
            }
            if pages.count > 1 { pages.removeFirst() }
            return first
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Response.self, from: page)
    }

    nonisolated func post<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        lexicon: String, body: Body
    ) async throws -> Response {
        posted.withLock { $0.append(lexicon) }
        let decoder = JSONDecoder()
        switch lexicon {
        case "com.atproto.repo.createRecord":
            return try decoder.decode(Response.self, from: createRecordFixture)
        case "com.atproto.repo.deleteRecord":
            return try decoder.decode(Response.self, from: Data("{}".utf8))
        default:
            throw ATError.unknown("unexpected POST \(lexicon) in test")
        }
    }

    nonisolated func upload<Response: Decodable & Sendable>(
        lexicon: String, data: Data, mimeType: String
    ) async throws -> Response {
        throw ATError.unknown("unexpected upload \(lexicon) in test")
    }
}

// MARK: - Tests

@MainActor
@Suite("ListsStore optimistic create/delete (#0203)")
struct ListsStoreTests {

    @Test("Created list appears immediately even when the post-create re-fetch is stale")
    func optimisticInsertSurvivesStaleRefetch() async throws {
        // Every getLists response is stale (empty) — the AppView never
        // catches up within the test. This is the exact #0203 repro.
        let client = ListsScriptedClient(listsPages: [emptyListsFixture])
        let store = ListsStore(network: client, accountStore: try await makeAccountStore())

        await store.loadLists(actorDID: viewerDID.rawValue)
        #expect(store.lists.isEmpty)

        await store.createList(name: "UITest-0203 List", description: "desc", purpose: "app.bsky.graph.defs#curatelist")

        #expect(store.error == nil)
        #expect(store.lists.count == 1)
        let inserted = try #require(store.lists.first)
        #expect(inserted.uri.rawValue == newListURI)
        #expect(inserted.name == "UITest-0203 List")
        #expect(inserted.description == "desc")
        #expect(inserted.creator.did == viewerDID)
        #expect(inserted.creator.handle.rawValue == "viewer.test")
        // The post-create re-fetch ran and returned the stale empty page,
        // yet the optimistic insert survived reconciliation.
        #expect(client.listsGetCount >= 2)

        // A later manual refresh that is still stale must not wipe it either.
        await store.loadLists(actorDID: viewerDID.rawValue)
        #expect(store.lists.count == 1)
        #expect(store.lists.first?.uri.rawValue == newListURI)
    }

    @Test("Reconciliation de-dupes by URI once the indexed server copy arrives")
    func reconciliationPrefersServerCopy() async throws {
        // Page sequence: initial load (empty) → post-create re-fetch
        // (stale, empty) → manual refresh (indexed copy present).
        let client = ListsScriptedClient(listsPages: [
            emptyListsFixture, emptyListsFixture, indexedListsFixture,
        ])
        let store = ListsStore(network: client, accountStore: try await makeAccountStore())

        await store.loadLists(actorDID: viewerDID.rawValue)
        await store.createList(name: "UITest-0203 List", description: "desc", purpose: "app.bsky.graph.defs#curatelist")
        #expect(store.lists.count == 1)
        // Optimistic copy: server count not known yet.
        #expect(store.lists.first?.listItemCount == 0)

        await store.loadLists(actorDID: viewerDID.rawValue)

        // Exactly one entry — no duplicate — and it is the server copy.
        #expect(store.lists.count == 1)
        let reconciled = try #require(store.lists.first)
        #expect(reconciled.uri.rawValue == newListURI)
        #expect(reconciled.listItemCount == 7)
    }

    @Test("Deleted list is not resurrected by a stale re-fetch")
    func deleteTombstoneBlocksStaleResurrection() async throws {
        // The AppView keeps returning the deleted list (it lags the PDS
        // delete); the tombstone must filter it out.
        let client = ListsScriptedClient(listsPages: [indexedListsFixture])
        let store = ListsStore(network: client, accountStore: try await makeAccountStore())

        await store.loadLists(actorDID: viewerDID.rawValue)
        #expect(store.lists.count == 1)

        await store.deleteList(uri: ATURI(rawValue: newListURI))
        #expect(store.error == nil)
        #expect(client.postedLexicons.contains("com.atproto.repo.deleteRecord"))
        #expect(store.lists.isEmpty)

        await store.loadLists(actorDID: viewerDID.rawValue)
        #expect(store.lists.isEmpty, "stale getLists response resurrected a deleted list")
    }

    @Test("Create followed by delete before indexing leaves the hub empty")
    func createThenDeleteBeforeIndexing() async throws {
        let client = ListsScriptedClient(listsPages: [emptyListsFixture])
        let store = ListsStore(network: client, accountStore: try await makeAccountStore())

        await store.loadLists(actorDID: viewerDID.rawValue)
        await store.createList(name: "UITest-0203 List", description: nil, purpose: "app.bsky.graph.defs#curatelist")
        #expect(store.lists.count == 1)

        await store.deleteList(uri: ATURI(rawValue: newListURI))
        #expect(store.lists.isEmpty)

        // Neither the optimistic insert nor a stale page brings it back.
        await store.loadLists(actorDID: viewerDID.rawValue)
        #expect(store.lists.isEmpty)
    }
}
