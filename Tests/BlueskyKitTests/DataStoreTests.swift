import Testing
import Foundation
@testable import BlueskyDataStore
import BlueskyKit

// MARK: - UserDefaultsPreferencesStore

@Suite("UserDefaultsPreferencesStore")
struct UserDefaultsPreferencesStoreTests {

    // Each test gets a fresh struct instance, so UUID() produces a unique suite name per test.
    let store = UserDefaultsPreferencesStore(suiteName: "test.bluesky.prefs.\(UUID().uuidString)")

    @Test func setAndGetString() throws {
        try store.set("hello", for: "greeting")
        let value = try store.get(String.self, for: "greeting")
        #expect(value == "hello")
    }

    @Test func getReturnsNilForAbsentKey() throws {
        let value = try store.get(String.self, for: "nonexistent-key")
        #expect(value == nil)
    }

    @Test func remove() throws {
        try store.set(42, for: "count")
        store.remove(for: "count")
        let value = try store.get(Int.self, for: "count")
        #expect(value == nil)
    }

    @Test func overwrite() throws {
        try store.set("first", for: "item")
        try store.set("second", for: "item")
        let value = try store.get(String.self, for: "item")
        #expect(value == "second")
    }

    @Test func setCodableStruct() throws {
        struct Prefs: Codable, Sendable, Equatable { var theme: String; var fontSize: Int }
        let prefs = Prefs(theme: "dark", fontSize: 16)
        try store.set(prefs, for: "prefs")
        let loaded = try store.get(Prefs.self, for: "prefs")
        #expect(loaded == prefs)
    }
}

// MARK: - SwiftDataCacheStore

@Suite("SwiftDataCacheStore")
struct SwiftDataCacheStoreTests {

    @Test func storeAndFetch() async throws {
        let cache = try SwiftDataCacheStore.inMemory()
        try await cache.store("cached-value", for: "key1", ttl: nil)
        let result = try await cache.fetch(String.self, for: "key1")
        #expect(result?.value == "cached-value")
        #expect(result?.isExpired == false)
    }

    @Test func fetchReturnsNilForAbsentKey() async throws {
        let cache = try SwiftDataCacheStore.inMemory()
        let result = try await cache.fetch(String.self, for: "absent")
        #expect(result == nil)
    }

    @Test func expiredEntryIsMarked() async throws {
        let cache = try SwiftDataCacheStore.inMemory()
        // ttl of -1 means the entry is already past its expiry
        try await cache.store("stale", for: "stale-key", ttl: -1)
        let result = try await cache.fetch(String.self, for: "stale-key")
        #expect(result?.value == "stale")
        #expect(result?.isExpired == true)
    }

    @Test func freshEntryIsNotExpired() async throws {
        let cache = try SwiftDataCacheStore.inMemory()
        try await cache.store("fresh", for: "fresh-key", ttl: 3600)
        let result = try await cache.fetch(String.self, for: "fresh-key")
        #expect(result?.value == "fresh")
        #expect(result?.isExpired == false)
    }

    @Test func evict() async throws {
        let cache = try SwiftDataCacheStore.inMemory()
        try await cache.store("value", for: "evict-key", ttl: nil)
        try await cache.evict(for: "evict-key")
        let result = try await cache.fetch(String.self, for: "evict-key")
        #expect(result == nil)
    }

    @Test func evictAll() async throws {
        let cache = try SwiftDataCacheStore.inMemory()
        try await cache.store("a", for: "key-a", ttl: nil)
        try await cache.store("b", for: "key-b", ttl: nil)
        try await cache.evictAll()
        let a = try await cache.fetch(String.self, for: "key-a")
        let b = try await cache.fetch(String.self, for: "key-b")
        #expect(a == nil)
        #expect(b == nil)
    }

    @Test func storeOverwritesExistingEntry() async throws {
        let cache = try SwiftDataCacheStore.inMemory()
        try await cache.store("original", for: "upsert-key", ttl: nil)
        try await cache.store("updated", for: "upsert-key", ttl: nil)
        let result = try await cache.fetch(String.self, for: "upsert-key")
        #expect(result?.value == "updated")
    }

    @Test func storeCodableStruct() async throws {
        struct Post: Codable, Sendable, Equatable { var id: String; var text: String }
        let post = Post(id: "abc", text: "Hello Bluesky!")
        let cache = try SwiftDataCacheStore.inMemory()
        try await cache.store(post, for: "post:abc", ttl: nil)
        let result = try await cache.fetch(Post.self, for: "post:abc")
        #expect(result?.value == post)
    }

    @Test func noTTLEntryIsNeverExpired() async throws {
        let cache = try SwiftDataCacheStore.inMemory()
        try await cache.store("permanent", for: "perm-key", ttl: nil)
        let result = try await cache.fetch(String.self, for: "perm-key")
        #expect(result?.isExpired == false)
    }
}
