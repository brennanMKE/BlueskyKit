import Testing
import Foundation
import Synchronization
import BlueskyKit
import BlueskyCore
import BlueskyLists

// MARK: - Fixtures

private let ownerDID = DID(rawValue: "did:plc:owner0204")
private let subjectDID = DID(rawValue: "did:plc:subject0204")
private let ownedListURI = "at://did:plc:owner0204/app.bsky.graph.list/3list0204"
private let otherListURI = "at://did:plc:someoneelse/app.bsky.graph.list/3other0204"
private let itemURI = "at://did:plc:owner0204/app.bsky.graph.listitem/3item0204"
private let foreignItemURI = "at://did:plc:someoneelse/app.bsky.graph.listitem/3item0204"

/// `com.atproto.repo.createRecord` response for the new listitem record.
private let createItemFixture = Data("""
{"uri": "\(itemURI)", "cid": "bafyreilistitem0204"}
""".utf8)

private func listJSON(uri: String, creator: String, itemCount: Int) -> String {
    """
    {
      "uri": "\(uri)",
      "cid": "bafyreilist0204",
      "creator": {"did": "\(creator)", "handle": "owner.test"},
      "name": "UITest-0204 List",
      "purpose": "app.bsky.graph.defs#curatelist",
      "labels": [],
      "listItemCount": \(itemCount)
    }
    """
}

/// `getList` page for the owned list before the AppView has indexed any
/// member (the #0204 add race condition).
private let emptyMembersFixture = Data("""
{"list": \(listJSON(uri: ownedListURI, creator: ownerDID.rawValue, itemCount: 0)), "items": []}
""".utf8)

/// `getList` page where the AppView has caught up: the indexed copy of the
/// added member is present (distinguishable from the optimistic insert by
/// the server-resolved displayName).
private let indexedMembersFixture = Data("""
{
  "list": \(listJSON(uri: ownedListURI, creator: ownerDID.rawValue, itemCount: 1)),
  "items": [
    {
      "uri": "\(itemURI)",
      "subject": {"did": "\(subjectDID.rawValue)", "handle": "subject.test", "displayName": "Indexed Subject"}
    }
  ]
}
""".utf8)

/// `getList` page for a list the viewer does NOT own, containing one member
/// whose listitem record lives in the other owner's repo.
private let foreignListFixture = Data("""
{
  "list": \(listJSON(uri: otherListURI, creator: "did:plc:someoneelse", itemCount: 1)),
  "items": [
    {
      "uri": "\(foreignItemURI)",
      "subject": {"did": "\(subjectDID.rawValue)", "handle": "subject.test"}
    }
  ]
}
""".utf8)

private func subjectProfile() -> ProfileBasic {
    ProfileBasic(
        did: subjectDID,
        handle: Handle(rawValue: "subject.test"),
        displayName: "Subject",
        avatar: nil
    )
}

// MARK: - Test doubles

private final class MembershipMockAccountStore: AccountStore, @unchecked Sendable {
    func save(_ account: StoredAccount) async throws {}
    func loadAll() async throws -> [StoredAccount] { [] }
    func load(did: DID) async throws -> StoredAccount? { nil }
    func remove(did: DID) async throws {}
    func setCurrentDID(_ did: DID?) async throws {}
    func loadCurrentDID() async throws -> DID? { ownerDID }
}

/// `NetworkClient` that serves a queue of canned `getList` pages (the last
/// page repeats once the queue drains) plus fixed `createRecord` /
/// `deleteRecord` responses, recording every POSTed lexicon and its
/// JSON-encoded body for inspection. Lexicons in `failingLexicons` throw.
private final class MembershipScriptedClient: NetworkClient, Sendable {
    private let listPages: Mutex<[Data]>
    private let posted = Mutex<[(lexicon: String, body: Data)]>([])
    private let failingLexicons: Set<String>

    init(listPages: [Data], failingLexicons: Set<String> = []) {
        self.listPages = Mutex(listPages)
        self.failingLexicons = failingLexicons
    }

    var postedRequests: [(lexicon: String, body: Data)] { posted.withLock { $0 } }

    /// Decoded JSON object of the most recent POST body for `lexicon`.
    func lastBodyJSON(for lexicon: String) throws -> [String: Any] {
        let body = posted.withLock { entries in
            entries.last { $0.lexicon == lexicon }?.body
        }
        let data = try #require(body, "no POST recorded for \(lexicon)")
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    nonisolated func get<Response: Decodable & Sendable>(
        lexicon: String, params: [String: String]
    ) async throws -> Response {
        guard lexicon == "app.bsky.graph.getList" else {
            throw ATError.unknown("unexpected GET \(lexicon) in test")
        }
        let page = listPages.withLock { pages -> Data in
            guard let first = pages.first else { return emptyMembersFixture }
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
        if failingLexicons.contains(lexicon) {
            throw ATError.unknown("scripted failure for \(lexicon)")
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(body)
        posted.withLock { $0.append((lexicon: lexicon, body: encoded)) }
        let decoder = JSONDecoder()
        switch lexicon {
        case "com.atproto.repo.createRecord":
            return try decoder.decode(Response.self, from: createItemFixture)
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
@Suite("ListDetailStore member management (#0204)")
struct ListMembershipTests {

    @Test("Add inserts the member optimistically and builds the right listitem record")
    func addMemberCreatesListitemAndInsertsOptimistically() async throws {
        let client = MembershipScriptedClient(listPages: [emptyMembersFixture])
        let store = ListDetailStore(network: client, accountStore: MembershipMockAccountStore())

        await store.load(listURI: ATURI(rawValue: ownedListURI))
        #expect(store.members.isEmpty)
        #expect(store.list?.listItemCount == 0)

        let ok = await store.addMember(subjectProfile())

        #expect(ok)
        #expect(store.error == nil)
        #expect(store.members.count == 1)
        let inserted = try #require(store.members.first)
        #expect(inserted.uri.rawValue == itemURI)
        #expect(inserted.subject.did == subjectDID)
        #expect(inserted.subject.handle.rawValue == "subject.test")
        // Header count tracks the optimistic add.
        #expect(store.list?.listItemCount == 1)

        // The createRecord body targets the viewer repo and carries an
        // app.bsky.graph.listitem record with the right list + subject.
        let body = try client.lastBodyJSON(for: "com.atproto.repo.createRecord")
        #expect(body["repo"] as? String == ownerDID.rawValue)
        #expect(body["collection"] as? String == "app.bsky.graph.listitem")
        let record = try #require(body["record"] as? [String: Any])
        #expect(record["$type"] as? String == "app.bsky.graph.listitem")
        #expect(record["list"] as? String == ownedListURI)
        #expect(record["subject"] as? String == subjectDID.rawValue)
        #expect(record["createdAt"] != nil)
    }

    @Test("Added member survives a stale re-fetch and de-dupes once the server copy arrives")
    func addedMemberSurvivesStaleRefetchAndDeDupes() async throws {
        // Page sequence: initial load (empty) → stale post-add re-fetch
        // (still empty) → indexed page (server copy present).
        let client = MembershipScriptedClient(listPages: [
            emptyMembersFixture, emptyMembersFixture, indexedMembersFixture,
        ])
        let store = ListDetailStore(network: client, accountStore: MembershipMockAccountStore())

        await store.load(listURI: ATURI(rawValue: ownedListURI))
        #expect(await store.addMember(subjectProfile()))
        #expect(store.members.count == 1)

        // Stale re-fetch (AppView hasn't indexed the listitem yet) must not
        // wipe the optimistic member.
        await store.load(listURI: ATURI(rawValue: ownedListURI))
        #expect(store.members.count == 1)
        #expect(store.members.first?.uri.rawValue == itemURI)
        // Optimistic copy carries the locally-known displayName.
        #expect(store.members.first?.subject.displayName == "Subject")

        // Indexed re-fetch: exactly one entry — no duplicate — and it is the
        // server copy.
        await store.load(listURI: ATURI(rawValue: ownedListURI))
        #expect(store.members.count == 1)
        let reconciled = try #require(store.members.first)
        #expect(reconciled.uri.rawValue == itemURI)
        #expect(reconciled.subject.displayName == "Indexed Subject")
    }

    @Test("Remove deletes the right rkey optimistically and tombstones against stale pages")
    func removeMemberDeletesRkeyOptimistically() async throws {
        // The AppView keeps returning the removed member (it lags the PDS
        // delete); the tombstone must filter it out.
        let client = MembershipScriptedClient(listPages: [indexedMembersFixture])
        let store = ListDetailStore(network: client, accountStore: MembershipMockAccountStore())

        await store.load(listURI: ATURI(rawValue: ownedListURI))
        #expect(store.members.count == 1)
        #expect(store.list?.listItemCount == 1)

        let ok = await store.removeMember(itemURI: ATURI(rawValue: itemURI))

        #expect(ok)
        #expect(store.error == nil)
        #expect(store.members.isEmpty)
        #expect(store.list?.listItemCount == 0)

        let body = try client.lastBodyJSON(for: "com.atproto.repo.deleteRecord")
        #expect(body["repo"] as? String == ownerDID.rawValue)
        #expect(body["collection"] as? String == "app.bsky.graph.listitem")
        #expect(body["rkey"] as? String == "3item0204")

        // A stale page still containing the item must not resurrect it.
        await store.load(listURI: ATURI(rawValue: ownedListURI))
        #expect(store.members.isEmpty, "stale getList page resurrected a removed member")
    }

    @Test("Remove reverts the optimistic removal when deleteRecord fails")
    func removeMemberRevertsOnFailure() async throws {
        let client = MembershipScriptedClient(
            listPages: [indexedMembersFixture],
            failingLexicons: ["com.atproto.repo.deleteRecord"]
        )
        let store = ListDetailStore(network: client, accountStore: MembershipMockAccountStore())

        await store.load(listURI: ATURI(rawValue: ownedListURI))
        #expect(store.members.count == 1)

        let ok = await store.removeMember(itemURI: ATURI(rawValue: itemURI))

        #expect(!ok)
        #expect(store.error != nil)
        // The member is restored so the UI doesn't lie about the removal.
        #expect(store.members.count == 1)
        #expect(store.members.first?.uri.rawValue == itemURI)
        #expect(store.list?.listItemCount == 1)
    }

    @Test("Non-owned list exposes no member mutations")
    func nonOwnedListExposesNoMutation() async throws {
        let client = MembershipScriptedClient(listPages: [foreignListFixture])
        let store = ListDetailStore(network: client, accountStore: MembershipMockAccountStore())

        await store.load(listURI: ATURI(rawValue: otherListURI))
        #expect(store.members.count == 1)

        let added = await store.addMember(
            ProfileBasic(
                did: DID(rawValue: "did:plc:somebody"),
                handle: Handle(rawValue: "somebody.test"),
                displayName: nil,
                avatar: nil
            )
        )
        #expect(!added)

        let removed = await store.removeMember(itemURI: ATURI(rawValue: foreignItemURI))
        #expect(!removed)

        // Neither mutation reached the network, and the list is untouched.
        #expect(client.postedRequests.isEmpty)
        #expect(store.members.count == 1)
    }
}
