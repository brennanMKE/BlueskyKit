import BlueskyCore

/// Contract for persisting `StoredAccount` values across launches.
///
/// The production implementation writes to the iOS/macOS Keychain.
/// Tests may use an in-memory implementation.
public protocol AccountStore: AnyObject, Sendable {
    /// Saves or overwrites the stored account for `account.account.did`.
    func save(_ account: StoredAccount) async throws

    /// Returns all stored accounts in the order they were saved.
    func loadAll() async throws -> [StoredAccount]

    /// Returns the stored account for `did`, or `nil` if not found.
    func load(did: DID) async throws -> StoredAccount?

    /// Deletes the stored account for `did`. No-ops if not found.
    func remove(did: DID) async throws

    /// Persists which DID is the currently active account.
    func setCurrentDID(_ did: DID?) async throws

    /// Returns the DID of the currently active account, or `nil` if none.
    func loadCurrentDID() async throws -> DID?
}
