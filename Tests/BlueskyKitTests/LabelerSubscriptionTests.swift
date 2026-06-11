import Testing
import Foundation
import Synchronization
import BlueskyKit
import BlueskyModeration
@testable import BlueskyCore

// MARK: - Fixtures

/// `app.bsky.actor.getPreferences` payload for the labeler tests: a
/// `labelersPref` with two subscriptions plus the other prefs that must
/// survive a labeler write untouched — including an *unmodeled* `$type`.
private func labelerPrefsFixture(labelerDIDs: [String] = ["did:plc:labeler1", "did:plc:labeler2"]) -> Data {
    let labelers = labelerDIDs.map { "{\"did\": \"\($0)\"}" }.joined(separator: ", ")
    return Data("""
    {
      "preferences": [
        {"$type": "app.bsky.actor.defs#adultContentPref", "enabled": true},
        {"$type": "app.bsky.actor.defs#savedFeedsPrefV2", "items": [
          {"id": "aaa", "type": "timeline", "value": "following", "pinned": true}
        ]},
        {"$type": "app.bsky.actor.defs#labelersPref", "labelers": [\(labelers)]},
        {"$type": "app.bsky.actor.defs#postLanguagesPref", "languages": ["en"]},
        {"$type": "app.bsky.actor.defs#bskyAppStatePref", "queuedNudges": ["nudge-one"], "activeProgressGuide": {"guide": "like-10-and-follow-7", "numLikes": 3}}
      ]
    }
    """.utf8)
}

// MARK: - Test double

/// `NetworkClient` that serves a canned `getPreferences` payload and an empty
/// `labeler.getServices` view list, recording every GET and POST.
private final class LabelerPrefsClient: NetworkClient, Sendable {
    private let prefsData: Data
    private let posted = Mutex<[(lexicon: String, body: Data)]>([])
    private let gets = Mutex<[(lexicon: String, params: [String: String])]>([])

    init(prefsData: Data) {
        self.prefsData = prefsData
    }

    var postedBodies: [(lexicon: String, body: Data)] { posted.withLock { $0 } }
    var getRequests: [(lexicon: String, params: [String: String])] { gets.withLock { $0 } }

    nonisolated func get<Response: Decodable & Sendable>(
        lexicon: String, params: [String: String]
    ) async throws -> Response {
        gets.withLock { $0.append((lexicon, params)) }
        switch lexicon {
        case "app.bsky.actor.getPreferences":
            return try JSONDecoder().decode(Response.self, from: prefsData)
        case "app.bsky.labeler.getServices":
            return try JSONDecoder().decode(Response.self, from: Data("{\"views\": []}".utf8))
        default:
            throw ATError.unknown("unexpected GET \(lexicon) in test")
        }
    }

    nonisolated func post<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        lexicon: String, body: Body
    ) async throws -> Response {
        let data = try JSONEncoder().encode(body)
        posted.withLock { $0.append((lexicon, data)) }
        return try JSONDecoder().decode(Response.self, from: Data("{}".utf8))
    }

    nonisolated func upload<Response: Decodable & Sendable>(
        lexicon: String, data: Data, mimeType: String
    ) async throws -> Response {
        throw ATError.unknown("unexpected upload in test")
    }
}

// MARK: - Helpers

private struct LabelerPrefsEnvelope: Decodable {
    let preferences: [JSONValue]
}

private func prefEntries(_ data: Data) throws -> [JSONValue] {
    try JSONDecoder().decode(LabelerPrefsEnvelope.self, from: data).preferences
}

private func labelerDIDs(in entries: [JSONValue]) -> [String] {
    entries
        .first { $0.typeDiscriminator == ActorPreferenceType.labelers }?
        .objectValue?["labelers"]?
        .arrayValue?
        .compactMap { $0.objectValue?["did"]?.stringValue }
        ?? []
}

// MARK: - Tests

@MainActor
@Suite("Labeler subscriptions (#0202)")
struct LabelerSubscriptionTests {

    @Test("Subscribe appends the DID to labelersPref and preserves every other preference")
    func subscribeWritesLabelersPref() async throws {
        let fixture = labelerPrefsFixture()
        let client = LabelerPrefsClient(prefsData: fixture)
        let store = LabelerProfileStore(network: client)

        await store.subscribe(labelerDID: "did:plc:labeler3")

        #expect(store.error == nil)
        #expect(store.isSubscribed)
        let put = try #require(client.postedBodies.first)
        #expect(put.lexicon == "app.bsky.actor.putPreferences")
        let out = try prefEntries(put.body)
        #expect(labelerDIDs(in: out) == ["did:plc:labeler1", "did:plc:labeler2", "did:plc:labeler3"])

        // Every non-labeler entry rode through verbatim — including the
        // unmodeled `bskyAppStatePref`.
        let current = try prefEntries(fixture)
        for entry in current where entry.typeDiscriminator != ActorPreferenceType.labelers {
            #expect(out.contains(entry), "expected \(entry.typeDiscriminator ?? "?") to survive the labeler write")
        }
        #expect(out.count == current.count)
    }

    @Test("Unsubscribe removes only the targeted DID")
    func unsubscribeRemovesOnlyTargetedDID() async throws {
        let fixture = labelerPrefsFixture()
        let client = LabelerPrefsClient(prefsData: fixture)
        let store = LabelerProfileStore(network: client)

        await store.unsubscribe(labelerDID: "did:plc:labeler1")

        #expect(store.error == nil)
        #expect(!store.isSubscribed)
        let put = try #require(client.postedBodies.first)
        let out = try prefEntries(put.body)
        #expect(labelerDIDs(in: out) == ["did:plc:labeler2"])
        // Other prefs untouched.
        let current = try prefEntries(fixture)
        for entry in current where entry.typeDiscriminator != ActorPreferenceType.labelers {
            #expect(out.contains(entry))
        }
    }

    @Test("Subscribe is a no-op when the DID is already in labelersPref")
    func subscribeSkipsWhenAlreadySubscribed() async throws {
        let client = LabelerPrefsClient(prefsData: labelerPrefsFixture())
        let store = LabelerProfileStore(network: client)

        await store.subscribe(labelerDID: "did:plc:labeler1")

        #expect(store.error == nil)
        #expect(store.isSubscribed)
        #expect(client.postedBodies.isEmpty, "already-subscribed must skip the put")
    }

    @Test("Unsubscribe is a no-op when the DID is not in labelersPref")
    func unsubscribeSkipsWhenNotSubscribed() async throws {
        let client = LabelerPrefsClient(prefsData: labelerPrefsFixture())
        let store = LabelerProfileStore(network: client)

        await store.unsubscribe(labelerDID: "did:plc:labeler9")

        #expect(store.error == nil)
        #expect(client.postedBodies.isEmpty, "not-subscribed must skip the put")
    }

    @Test("isSubscribed derives from labelersPref")
    func isSubscribedDerivesFromLabelersPref() async throws {
        let client = LabelerPrefsClient(prefsData: labelerPrefsFixture())

        let subscribed = LabelerProfileStore(network: client)
        await subscribed.load(labelerDID: "did:plc:labeler1")
        #expect(subscribed.isSubscribed)

        let notSubscribed = LabelerProfileStore(network: client)
        await notSubscribed.load(labelerDID: "did:plc:labeler9")
        #expect(!notSubscribed.isSubscribed)
    }

    @Test("Bluesky's app labeler is implicitly subscribed and never written to labelersPref")
    func appLabelerIsImplicit() async throws {
        let bskyDID = AppLabelers.blueskyModerationDID.rawValue
        #expect(bskyDID == "did:plc:ar7c4by46qjdydhdevvrndac")

        // Not present in labelersPref, yet always subscribed (RN's
        // `isLabelerSubscribed` short-circuits on `isAppLabeler`).
        let client = LabelerPrefsClient(prefsData: labelerPrefsFixture())
        let store = LabelerProfileStore(network: client)
        await store.load(labelerDID: bskyDID)
        #expect(store.isSubscribed)

        // Subscribe and unsubscribe never touch the server prefs.
        await store.subscribe(labelerDID: bskyDID)
        await store.unsubscribe(labelerDID: bskyDID)
        #expect(store.isSubscribed, "app labeler stays subscribed")
        #expect(store.error == nil)
        #expect(client.postedBodies.isEmpty, "app labeler must never be written to labelersPref")
    }

    @Test("Subscribe fails without a write once MAX_LABELERS is reached")
    func subscribeEnforcesMaxLabelers() async throws {
        let twenty = (1...AppLabelers.maxLabelers).map { "did:plc:labeler\($0)" }
        let client = LabelerPrefsClient(prefsData: labelerPrefsFixture(labelerDIDs: twenty))
        let store = LabelerProfileStore(network: client)

        await store.subscribe(labelerDID: "did:plc:labeler21")

        #expect(store.error != nil, "MAX_LABELERS must surface an error")
        #expect(!store.isSubscribed)
        #expect(client.postedBodies.isEmpty, "over-limit subscribe must not write")
    }

    @Test("Moderation hub resolves the implicit app labeler ahead of labelersPref entries")
    func hubResolvesAppLabelerFirst() async throws {
        let client = LabelerPrefsClient(prefsData: labelerPrefsFixture())
        let store = ModerationStore(network: client, accountStore: NoOpAccountStore())

        await store.loadSubscribedLabelers()

        // `subscribedLabelerDIDs` mirrors labelersPref verbatim (the app
        // labeler is implicit, not stored)…
        #expect(store.subscribedLabelerDIDs.map(\.rawValue) == ["did:plc:labeler1", "did:plc:labeler2"])
        // …but the getServices resolution set prepends the app labeler
        // (RN `useMyLabelersQuery`: appLabelers ∪ prefs labelers). One
        // request per DID: the appview rejects comma-joined `dids` values,
        // and `NetworkClient.get` cannot express repeated query keys.
        let getServices = client.getRequests
            .filter { $0.lexicon == "app.bsky.labeler.getServices" }
            .compactMap { $0.params["dids"] }
        #expect(getServices == ["did:plc:ar7c4by46qjdydhdevvrndac", "did:plc:labeler1", "did:plc:labeler2"])
    }
}

// MARK: - AccountStore stub

private final class NoOpAccountStore: AccountStore, Sendable {
    nonisolated func save(_ account: StoredAccount) async throws {}
    nonisolated func loadAll() async throws -> [StoredAccount] { [] }
    nonisolated func load(did: DID) async throws -> StoredAccount? { nil }
    nonisolated func remove(did: DID) async throws {}
    nonisolated func setCurrentDID(_ did: DID?) async throws {}
    nonisolated func loadCurrentDID() async throws -> DID? { nil }
}
