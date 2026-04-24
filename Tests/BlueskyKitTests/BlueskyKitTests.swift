import Testing
import Foundation
@testable import BlueskyKit
import BlueskyCore

// MARK: - Mock implementations

// SessionManaging is @MainActor (manages UI-visible session state).
@MainActor
private final class MockSessionManager: SessionManaging {
    var currentAccount: Account? = nil
    var accounts: [Account] = []

    func login(identifier: String, password: String, authFactorToken: String?) async throws -> Account {
        throw ATError.unauthenticated
    }
    func resumeSession(_ stored: StoredAccount) async throws {}
    func switchAccount(to did: DID) async throws {}
    func logout(did: DID) async throws {}
    func removeAccount(did: DID) async throws {}
}

// AccountStore, PreferencesStore, NetworkClient have nonisolated requirements.
// In the test target (no defaultIsolation), class methods are nonisolated by default.
// @unchecked Sendable is appropriate for single-threaded test use.

private final class MockAccountStore: AccountStore, @unchecked Sendable {
    private var store: [String: StoredAccount] = [:]
    private var currentDID: DID?

    func save(_ account: StoredAccount) async throws { store[account.account.did.rawValue] = account }
    func loadAll() async throws -> [StoredAccount] { Array(store.values) }
    func load(did: DID) async throws -> StoredAccount? { store[did.rawValue] }
    func remove(did: DID) async throws { store[did.rawValue] = nil }
    func setCurrentDID(_ did: DID?) async throws { currentDID = did }
    func loadCurrentDID() async throws -> DID? { currentDID }
}

private final class MockPreferencesStore: PreferencesStore, @unchecked Sendable {
    private var store: [String: Data] = [:]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func set<T: Codable & Sendable>(_ value: T, for key: String) throws {
        store[key] = try encoder.encode(value)
    }
    func get<T: Codable & Sendable>(_ type: T.Type, for key: String) throws -> T? {
        guard let data = store[key] else { return nil }
        return try decoder.decode(type, from: data)
    }
    func remove(for key: String) { store[key] = nil }
}

private final class MockNetworkClient: NetworkClient, @unchecked Sendable {
    func get<Response: Decodable & Sendable>(lexicon: String, params: [String: String]) async throws -> Response {
        throw ATError.unknown("MockNetworkClient: no fixture for \(lexicon)")
    }
    func post<Body: Encodable & Sendable, Response: Decodable & Sendable>(lexicon: String, body: Body) async throws -> Response {
        throw ATError.unknown("MockNetworkClient: no fixture for \(lexicon)")
    }
}

private final class MockCacheStore: CacheStore, @unchecked Sendable {
    private var store: [String: (data: Data, expiresAt: Date?)] = [:]

    func store<T: Codable & Sendable>(_ value: T, for key: String, ttl: TimeInterval?) async throws {
        let data = try JSONEncoder().encode(value)
        store[key] = (data, ttl.map { Date(timeIntervalSinceNow: $0) })
    }
    func fetch<T: Codable & Sendable>(_ type: T.Type, for key: String) async throws -> CacheResult<T>? {
        guard let entry = store[key] else { return nil }
        let value = try JSONDecoder().decode(T.self, from: entry.data)
        let isExpired = entry.expiresAt.map { $0 < .now } ?? false
        return CacheResult(value: value, isExpired: isExpired)
    }
    func evict(for key: String) async throws { store[key] = nil }
    func evictAll() async throws { store.removeAll() }
}

// MARK: - BlueskyEnvironment tests

@MainActor
@Suite("BlueskyEnvironment")
struct BlueskyEnvironmentTests {
    @Test("assembles with mock implementations")
    func assembleWithMocks() {
        let env = BlueskyEnvironment(
            session: MockSessionManager(),
            accounts: MockAccountStore(),
            preferences: MockPreferencesStore(),
            network: MockNetworkClient(),
            cache: MockCacheStore()
        )
        #expect(env.session.currentAccount == nil)
        #expect(env.session.accounts.isEmpty)
    }
}

// MARK: - BlueskyCore Codable tests

@Suite("BlueskyCore Codable")
struct CoreCodableTests {
    @Test("DID round-trips through JSON")
    func didRoundTrip() throws {
        let did = DID(rawValue: "did:plc:abc123")
        let data = try JSONEncoder().encode(did)
        let decoded = try JSONDecoder().decode(DID.self, from: data)
        #expect(decoded == did)
    }

    @Test("Handle round-trips through JSON")
    func handleRoundTrip() throws {
        let handle = Handle(rawValue: "user.bsky.social")
        let data = try JSONEncoder().encode(handle)
        let decoded = try JSONDecoder().decode(Handle.self, from: data)
        #expect(decoded == handle)
    }

    @Test("ATURI parses components")
    func atURIComponents() {
        let uri = ATURI(rawValue: "at://did:plc:abc/app.bsky.feed.post/rkey123")
        #expect(uri.repo == "did:plc:abc")
        #expect(uri.collection == "app.bsky.feed.post")
        #expect(uri.rkey == "rkey123")
    }

    @Test("PagedResult preserves items and cursor")
    func pagedResult() {
        let result = PagedResult(items: [1, 2, 3], cursor: "next-page")
        #expect(result.items == [1, 2, 3])
        #expect(result.cursor == "next-page")
    }

    @Test("FacetFeature mention round-trips")
    func facetMentionRoundTrip() throws {
        let mention = FacetFeature.mention(did: DID(rawValue: "did:plc:xyz"))
        let data = try JSONEncoder().encode(mention)
        let decoded = try JSONDecoder().decode(FacetFeature.self, from: data)
        guard case .mention(let did) = decoded else {
            Issue.record("Expected .mention, got \(decoded)")
            return
        }
        #expect(did.rawValue == "did:plc:xyz")
    }
}

// MARK: - MockPreferencesStore unit tests

@Suite("MockPreferencesStore")
struct PreferencesStoreTests {
    @Test("stores and retrieves a value")
    func roundTrip() throws {
        let store = MockPreferencesStore()
        try store.set("hello", for: "greeting")
        let value = try store.get(String.self, for: "greeting")
        #expect(value == "hello")
    }

    @Test("returns nil for missing key")
    func missingKey() throws {
        #expect(try MockPreferencesStore().get(String.self, for: "missing") == nil)
    }

    @Test("remove clears a key")
    func removeKey() throws {
        let store = MockPreferencesStore()
        try store.set(42, for: "count")
        store.remove(for: "count")
        #expect(try store.get(Int.self, for: "count") == nil)
    }
}
