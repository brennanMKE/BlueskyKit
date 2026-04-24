import BlueskyCore

/// Contract for reading and writing typed user preferences.
///
/// The production implementation wraps `UserDefaults`. Tests use in-memory storage.
/// Values are stored as JSON-encoded `Codable` blobs under plain string keys.
public protocol PreferencesStore: AnyObject, Sendable {
    /// Encodes `value` as JSON and stores it under `key`.
    nonisolated func set<T: Codable & Sendable>(_ value: T, for key: String) throws

    /// Decodes and returns the value stored under `key`, or `nil` if absent.
    nonisolated func get<T: Codable & Sendable>(_ type: T.Type, for key: String) throws -> T?

    /// Removes the value stored under `key`. No-ops if not found.
    nonisolated func remove(for key: String)
}
