import Foundation
import BlueskyCore

// CacheResult<T> lives in BlueskyCore (no default isolation) so it can be constructed
// and accessed from any actor context without @MainActor restrictions.

/// Contract for a key/value cache with optional per-entry TTL.
///
/// All requirements are `nonisolated async` so implementations can be actor-isolated.
/// The `fetch` method returns stale entries rather than `nil` — callers decide
/// whether to show stale content or trigger a background refresh.
public protocol CacheStore: AnyObject, Sendable {
    /// Encodes `value` as JSON and stores it under `key`.
    /// Pass `nil` for `ttl` to cache indefinitely.
    nonisolated func store<T: Codable & Sendable>(
        _ value: T, for key: String, ttl: TimeInterval?
    ) async throws

    /// Returns the cached entry for `key`, or `nil` if no entry exists.
    /// Always returns the entry even if expired; check `isExpired` to decide
    /// whether to refresh in the background.
    nonisolated func fetch<T: Codable & Sendable>(
        _ type: T.Type, for key: String
    ) async throws -> CacheResult<T>?

    /// Removes the entry for `key`. No-ops if absent.
    nonisolated func evict(for key: String) async throws

    /// Removes all cached entries.
    nonisolated func evictAll() async throws
}
