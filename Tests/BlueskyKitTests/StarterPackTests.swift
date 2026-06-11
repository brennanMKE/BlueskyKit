// StarterPackTests.swift
//
// #0206 — Starter pack reachability: decoding of the actor-level starter
// pack listing (the profile Starter Packs tab) and the owner delete flow
// (starter-pack record + backing list + listitem sweep).

import Testing
import Foundation
import Synchronization
import BlueskyKit
import BlueskyCore
import BlueskyLists

// MARK: - Fixtures

private let creatorDID = DID(rawValue: "did:plc:creator0206")
private let packURI = "at://did:plc:creator0206/app.bsky.graph.starterpack/3pack0206"
private let listURI = "at://did:plc:creator0206/app.bsky.graph.list/3list0206"

private let iso8601: JSONDecoder = {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    return d
}()

/// `app.bsky.graph.getActorStarterPacks` page — the lexicon's
/// `starterPackViewBasic` keeps name/description inside the raw `record`.
private let actorStarterPacksFixture = Data("""
{
  "starterPacks": [
    {
      "uri": "\(packURI)",
      "cid": "bafypack0206",
      "record": {
        "$type": "app.bsky.graph.starterpack",
        "name": "Swift Friends",
        "description": "People building with Swift.",
        "list": "\(listURI)",
        "createdAt": "2026-06-10T12:00:00Z"
      },
      "creator": {"did": "\(creatorDID.rawValue)", "handle": "creator.test", "labels": []},
      "listItemCount": 9,
      "joinedWeekCount": 2,
      "joinedAllTimeCount": 120,
      "labels": [],
      "indexedAt": "2026-06-10T12:00:05Z"
    }
  ],
  "cursor": "page-2"
}
""".utf8)

/// Same page but with a missing `record` — must not fail the whole decode.
private let recordlessFixture = Data("""
{
  "starterPacks": [
    {
      "uri": "\(packURI)",
      "cid": "bafypack0206",
      "creator": {"did": "\(creatorDID.rawValue)", "handle": "creator.test", "labels": []},
      "labels": [],
      "indexedAt": "2026-06-10T12:00:05Z"
    }
  ]
}
""".utf8)

/// `com.atproto.repo.listRecords` page for the listitem sweep: two rows in
/// the pack's backing list, one belonging to a different list.
private let listItemRecordsFixture = Data("""
{
  "records": [
    {
      "uri": "at://did:plc:creator0206/app.bsky.graph.listitem/3item1",
      "cid": "bafyitem1",
      "value": {"$type": "app.bsky.graph.listitem", "list": "\(listURI)", "subject": "did:plc:member1", "createdAt": "2026-06-10T12:00:00Z"}
    },
    {
      "uri": "at://did:plc:creator0206/app.bsky.graph.listitem/3item2",
      "cid": "bafyitem2",
      "value": {"$type": "app.bsky.graph.listitem", "list": "\(listURI)", "subject": "did:plc:member2", "createdAt": "2026-06-10T12:00:01Z"}
    },
    {
      "uri": "at://did:plc:creator0206/app.bsky.graph.listitem/3other",
      "cid": "bafyother",
      "value": {"$type": "app.bsky.graph.listitem", "list": "at://did:plc:creator0206/app.bsky.graph.list/3unrelated", "subject": "did:plc:member3", "createdAt": "2026-06-10T12:00:02Z"}
    }
  ]
}
""".utf8)

private func makePackView() -> StarterPackView {
    StarterPackView(
        uri: ATURI(rawValue: packURI),
        cid: "bafypack0206",
        creator: ProfileBasic(
            did: creatorDID,
            handle: Handle(rawValue: "creator.test"),
            displayName: "Creator",
            avatar: nil
        ),
        list: ListBasic(
            uri: ATURI(rawValue: listURI),
            cid: "bafylist0206",
            name: "Swift Friends",
            purpose: "app.bsky.graph.defs#referencelist",
            avatar: nil
        ),
        indexedAt: .now
    )
}

private func makeAccountStore(currentDID: DID) async throws -> StarterPackMockAccountStore {
    let store = StarterPackMockAccountStore()
    try await store.setCurrentDID(currentDID)
    return store
}

// MARK: - Test doubles

private final class StarterPackMockAccountStore: AccountStore, @unchecked Sendable {
    private var currentDID: DID?
    func save(_ account: StoredAccount) async throws {}
    func loadAll() async throws -> [StoredAccount] { [] }
    func load(did: DID) async throws -> StoredAccount? { nil }
    func remove(did: DID) async throws {}
    func setCurrentDID(_ did: DID?) async throws { currentDID = did }
    func loadCurrentDID() async throws -> DID? { currentDID }
}

/// Serves a canned `listRecords` page and records every POST with its
/// JSON-encoded body so assertions can inspect the write fan-out.
private final class StarterPackScriptedClient: NetworkClient, Sendable {
    private let posted = Mutex<[(lexicon: String, body: Data)]>([])

    var postedRequests: [(lexicon: String, body: Data)] { posted.withLock { $0 } }
    var postedLexicons: [String] { postedRequests.map(\.lexicon) }

    nonisolated func get<Response: Decodable & Sendable>(
        lexicon: String, params: [String: String]
    ) async throws -> Response {
        guard lexicon == "com.atproto.repo.listRecords" else {
            throw ATError.unknown("unexpected GET \(lexicon) in test")
        }
        return try iso8601.decode(Response.self, from: listItemRecordsFixture)
    }

    nonisolated func post<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        lexicon: String, body: Body
    ) async throws -> Response {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(body)
        posted.withLock { $0.append((lexicon, data)) }
        switch lexicon {
        case "com.atproto.repo.applyWrites":
            return try iso8601.decode(Response.self, from: Data("{}".utf8))
        case "com.atproto.repo.deleteRecord":
            return try iso8601.decode(Response.self, from: Data("{}".utf8))
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

// MARK: - Decoding (#0206)

@Suite("Starter pack lexicon (#0206)")
struct StarterPackCodableTests {

    @Test("getActorStarterPacks lifts name/description out of the nested record")
    func decodeActorStarterPacks() throws {
        let page = try iso8601.decode(GetActorStarterPacksResponse.self, from: actorStarterPacksFixture)
        #expect(page.cursor == "page-2")
        let pack = try #require(page.starterPacks.first)
        #expect(pack.uri.rawValue == packURI)
        #expect(pack.name == "Swift Friends")
        #expect(pack.description == "People building with Swift.")
        #expect(pack.creator.handle.rawValue == "creator.test")
        #expect(pack.listItemCount == 9)
        #expect(pack.joinedAllTimeCount == 120)
    }

    @Test("A starter pack with a missing record decodes with fallback copy")
    func decodeRecordlessStarterPack() throws {
        let page = try iso8601.decode(GetActorStarterPacksResponse.self, from: recordlessFixture)
        let pack = try #require(page.starterPacks.first)
        #expect(pack.name == "Starter Pack")
        #expect(pack.description == nil)
        #expect(page.cursor == nil)
    }

    @Test("profile associated counts decode and gate the Starter Packs tab")
    func decodeProfileAssociated() throws {
        let json = Data("""
        {
          "did": "\(creatorDID.rawValue)",
          "handle": "creator.test",
          "associated": {"lists": 1, "feedgens": 0, "starterPacks": 3, "labeler": false}
        }
        """.utf8)
        let profile = try iso8601.decode(ProfileDetailed.self, from: json)
        #expect(profile.associated?.starterPacks == 3)
        #expect(profile.associated?.lists == 1)
        #expect(profile.associated?.labeler == false)
    }
}

// MARK: - Owner delete (#0206)

@MainActor
@Suite("Starter pack delete (#0206)")
struct StarterPackDeleteTests {

    @Test("Delete sweeps the backing list's items, then the list, then the pack")
    func deleteSweepsListItemsListAndPack() async throws {
        let client = StarterPackScriptedClient()
        let store = ListsStore(network: client, accountStore: try await makeAccountStore(currentDID: creatorDID))

        let ok = await store.deleteStarterPack(pack: makePackView())

        #expect(ok)
        #expect(store.error == nil)
        #expect(client.postedLexicons == [
            "com.atproto.repo.applyWrites",   // listitem sweep (one chunk)
            "com.atproto.repo.deleteRecord",  // backing list
            "com.atproto.repo.deleteRecord",  // starter pack record
        ])

        // The sweep deletes exactly the two rows belonging to the pack's
        // list — the unrelated listitem is left alone.
        let applyBody = try #require(client.postedRequests.first?.body)
        let applyJSON = try #require(try JSONSerialization.jsonObject(with: applyBody) as? [String: Any])
        let writes = try #require(applyJSON["writes"] as? [[String: Any]])
        #expect(writes.count == 2)
        let rkeys = Set(writes.compactMap { $0["rkey"] as? String })
        #expect(rkeys == ["3item1", "3item2"])
        #expect(writes.allSatisfy { ($0["$type"] as? String) == "com.atproto.repo.applyWrites#delete" })

        // Record deletes target the right collections and rkeys.
        let deletes = client.postedRequests.filter { $0.lexicon == "com.atproto.repo.deleteRecord" }
        let decoded = try deletes.map {
            try #require(try JSONSerialization.jsonObject(with: $0.body) as? [String: Any])
        }
        #expect(decoded[0]["collection"] as? String == "app.bsky.graph.list")
        #expect(decoded[0]["rkey"] as? String == "3list0206")
        #expect(decoded[1]["collection"] as? String == "app.bsky.graph.starterpack")
        #expect(decoded[1]["rkey"] as? String == "3pack0206")
    }

    @Test("Only the creator can delete a starter pack")
    func deleteRefusesNonCreator() async throws {
        let client = StarterPackScriptedClient()
        let store = ListsStore(
            network: client,
            accountStore: try await makeAccountStore(currentDID: DID(rawValue: "did:plc:someoneelse"))
        )

        let ok = await store.deleteStarterPack(pack: makePackView())

        #expect(!ok)
        #expect(store.error != nil)
        #expect(client.postedLexicons.isEmpty, "no writes may be issued for a pack the viewer doesn't own")
    }
}
