import Foundation
import BlueskyKit

/// `UserDefaults`-backed implementation of `PreferencesStore`.
///
/// `UserDefaults` is documented as thread-safe, so `@unchecked Sendable` suppresses
/// the concurrency warning for the stored reference. Pass a `suiteName` that matches
/// your App Group identifier to share preferences across app extensions.
public final class UserDefaultsPreferencesStore: PreferencesStore, @unchecked Sendable {

    private let defaults: UserDefaults

    public init(suiteName: String? = nil) {
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    public nonisolated func set<T: Codable & Sendable>(_ value: T, for key: String) throws {
        let data = try JSONEncoder().encode(value)
        defaults.set(data, forKey: key)
    }

    public nonisolated func get<T: Codable & Sendable>(_ type: T.Type, for key: String) throws -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try JSONDecoder().decode(T.self, from: data)
    }

    public nonisolated func remove(for key: String) {
        defaults.removeObject(forKey: key)
    }
}
