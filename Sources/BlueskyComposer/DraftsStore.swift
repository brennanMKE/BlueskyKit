import Foundation
import OSLog

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "co.sstools.Bluesky",
    category: "DraftsStore"
)

// MARK: - DraftsStoring

/// Persistence boundary for composer drafts. Marked `Sendable` so the
/// composer can hold a reference across actor hops (e.g. background save on
/// `Task.detached`) without warnings. The default implementation
/// (`UserDefaultsDraftsStore`) is `nonisolated`; tests inject the in-memory
/// `MockDraftsStore` and previews use `MockDraftsStore` too.
public protocol DraftsStoring: Sendable {
    func loadAll() async -> [Draft]
    func save(_ draft: Draft) async
    func delete(_ id: UUID) async
    func deleteAll() async
}

// MARK: - UserDefaultsDraftsStore

/// `UserDefaults`-backed `DraftsStoring`. Stores all drafts as a single
/// JSON-encoded array under `bluesky.composer.drafts`. Sized for tens of
/// drafts at most — beyond that, encode/decode cost on every save would push
/// us toward a SwiftData-backed implementation.
///
/// `UserDefaults` is documented as thread-safe so we mark `@unchecked
/// Sendable`. All mutating reads/writes are funnelled through `loadAll` /
/// `persist`, which read-modify-write the full array; concurrent writes from
/// different actors will race but draft persistence is single-writer in
/// practice (only the active composer writes), so we don't add a serial queue.
public final class UserDefaultsDraftsStore: DraftsStoring, @unchecked Sendable {
    public static let storageKey = "bluesky.composer.drafts"

    private let defaults: UserDefaults
    private let key: String

    public init(suiteName: String? = nil, key: String = UserDefaultsDraftsStore.storageKey) {
        self.defaults = UserDefaults(suiteName: suiteName) ?? .standard
        self.key = key
    }

    public func loadAll() async -> [Draft] {
        loadSync()
    }

    public func save(_ draft: Draft) async {
        var all = loadSync()
        if let idx = all.firstIndex(where: { $0.id == draft.id }) {
            all[idx] = draft
        } else {
            all.append(draft)
        }
        persist(all)
    }

    public func delete(_ id: UUID) async {
        var all = loadSync()
        all.removeAll(where: { $0.id == id })
        persist(all)
    }

    public func deleteAll() async {
        defaults.removeObject(forKey: key)
    }

    // MARK: - Internal

    private func loadSync() -> [Draft] {
        guard let data = defaults.data(forKey: key) else { return [] }
        do {
            return try JSONDecoder().decode([Draft].self, from: data)
        } catch {
            logger.error("drafts decode failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func persist(_ drafts: [Draft]) {
        do {
            let data = try JSONEncoder().encode(drafts)
            defaults.set(data, forKey: key)
        } catch {
            logger.error("drafts encode failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - MockDraftsStore

/// In-memory `DraftsStoring` for previews and tests. Marked `@unchecked
/// Sendable` because the underlying array mutation is only safe under
/// MainActor in the SwiftUI preview — actor-isolated callers should use a
/// real store.
public final class MockDraftsStore: DraftsStoring, @unchecked Sendable {
    private var storage: [Draft]

    public init(initial: [Draft] = []) {
        self.storage = initial
    }

    public func loadAll() async -> [Draft] {
        storage.sorted(by: { $0.updatedAt > $1.updatedAt })
    }

    public func save(_ draft: Draft) async {
        if let idx = storage.firstIndex(where: { $0.id == draft.id }) {
            storage[idx] = draft
        } else {
            storage.append(draft)
        }
    }

    public func delete(_ id: UUID) async {
        storage.removeAll(where: { $0.id == id })
    }

    public func deleteAll() async {
        storage.removeAll()
    }
}
