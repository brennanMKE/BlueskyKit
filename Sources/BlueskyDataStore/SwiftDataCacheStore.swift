import Foundation
import SwiftData
import BlueskyCore
import BlueskyKit

// MARK: - Persistent model

@Model
final class CacheEntry {
    @Attribute(.unique) var key: String
    var data: Data
    var expiresAt: Date?
    var storedAt: Date

    init(key: String, data: Data, expiresAt: Date?, storedAt: Date = .now) {
        self.key = key
        self.data = data
        self.expiresAt = expiresAt
        self.storedAt = storedAt
    }
}

// MARK: - SwiftDataCacheStore

/// SwiftData-backed implementation of `CacheStore`.
///
/// Each instance manages its own `ModelContainer`. All SwiftData operations run on the
/// actor's executor using per-call `ModelContext`s (lightweight; one context per operation
/// keeps the actor's state minimal and avoids cross-context change-tracking conflicts).
///
/// Pass `appGroupIdentifier` to store the database in the shared App Group container so
/// the notification extension can share the same cache.
public actor SwiftDataCacheStore: CacheStore {

    private let container: ModelContainer

    /// Creates a cache backed by persistent storage.
    /// - Parameter appGroupIdentifier: Optional App Group ID; if provided, the SwiftData
    ///   store is placed in the shared container so app extensions can share the cache.
    public init(appGroupIdentifier: String? = nil) throws {
        container = try Self.makeContainer(appGroupIdentifier: appGroupIdentifier, inMemory: false)
    }

    private init(container: ModelContainer) {
        self.container = container
    }

    /// Creates an in-memory cache suitable for tests and Xcode Previews.
    public static func inMemory() throws -> SwiftDataCacheStore {
        let c = try makeContainer(appGroupIdentifier: nil, inMemory: true)
        return SwiftDataCacheStore(container: c)
    }

    private static func makeContainer(appGroupIdentifier: String?, inMemory: Bool) throws -> ModelContainer {
        let schema = Schema([CacheEntry.self])
        let config: ModelConfiguration
        if inMemory {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else if let groupID = appGroupIdentifier,
                  let groupURL = FileManager.default.containerURL(
                      forSecurityApplicationGroupIdentifier: groupID) {
            let url = groupURL.appendingPathComponent("BlueskyCache.store")
            let exists = FileManager.default.fileExists(atPath: url.path)
            print("[Cache] App Group store URL: \(url.path) (exists=\(exists))")
            config = ModelConfiguration(schema: schema, url: url)
        } else {
            // Use an explicit path so the store location is consistent across launches.
            // ModelConfiguration(schema:) with no URL uses a SwiftData-generated name
            // that can vary, causing data written in one launch to be invisible the next.
            let support = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first ?? FileManager.default.temporaryDirectory
            let dir = support.appendingPathComponent(
                Bundle.main.bundleIdentifier ?? "co.sstools.bluesky", isDirectory: true
            )
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("BlueskyCache.store")
            let exists = FileManager.default.fileExists(atPath: url.path)
            print("[Cache] Local store URL: \(url.path) (exists=\(exists))")
            config = ModelConfiguration(schema: schema, url: url)
        }
        return try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - CacheStore (nonisolated wrappers)

    public nonisolated func store<T: Codable & Sendable>(
        _ value: T, for key: String, ttl: TimeInterval?
    ) async throws {
        try await _store(value, for: key, ttl: ttl)
    }

    public nonisolated func fetch<T: Codable & Sendable>(
        _ type: T.Type, for key: String
    ) async throws -> CacheResult<T>? {
        try await _fetch(type, for: key)
    }

    public nonisolated func evict(for key: String) async throws {
        try await _evict(for: key)
    }

    public nonisolated func evictAll() async throws {
        try await _evictAll()
    }

    // MARK: - Actor-isolated implementation

    private func _store<T: Codable & Sendable>(_ value: T, for key: String, ttl: TimeInterval?) throws {
        let data = try JSONEncoder().encode(value)
        let expiresAt = ttl.map { Date(timeIntervalSinceNow: $0) }
        let ctx = ModelContext(container)
        let targetKey = key
        try ctx.delete(model: CacheEntry.self, where: #Predicate { $0.key == targetKey })
        ctx.insert(CacheEntry(key: key, data: data, expiresAt: expiresAt))
        try ctx.save()
    }

    private func _fetch<T: Codable & Sendable>(_ type: T.Type, for key: String) throws -> CacheResult<T>? {
        let ctx = ModelContext(container)
        let targetKey = key
        let descriptor = FetchDescriptor<CacheEntry>(predicate: #Predicate { $0.key == targetKey })
        let results = try ctx.fetch(descriptor)
        guard let entry = results.first else { return nil }
        let value = try JSONDecoder().decode(T.self, from: entry.data)
        let isExpired = entry.expiresAt.map { $0 < .now } ?? false
        return CacheResult(value: value, isExpired: isExpired)
    }

    private func _evict(for key: String) throws {
        let ctx = ModelContext(container)
        let targetKey = key
        try ctx.delete(model: CacheEntry.self, where: #Predicate { $0.key == targetKey })
        try ctx.save()
    }

    private func _evictAll() throws {
        let ctx = ModelContext(container)
        try ctx.delete(model: CacheEntry.self)
        try ctx.save()
    }
}
