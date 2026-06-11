import Foundation
import BlueskyCore

/// Serialized read-modify-write executor for `app.bsky.actor.putPreferences`
/// (#0201).
///
/// `putPreferences` **replaces** the account's entire `app.bsky` preference
/// namespace, so a body carrying only the preference being changed silently
/// deletes every other server-side preference. RN never does that: every
/// preference mutation in `@atproto/api`'s `BskyAgent` goes through
/// `updatePreferences(cb)` — fetch the full `preferences` array, apply the
/// change, put the **whole array** back, under a mutex (`#prefsLock`).
///
/// This actor is the SwiftUI client's equivalent. `update` fetches the
/// caller's full preferences array fresh, applies one `PreferencesMutation`
/// (which only removes/appends the targeted entries — unknown `$type`s ride
/// through verbatim via `GetPreferencesResponse.rawPreferences`), and writes
/// the complete merged array back. An internal task chain serializes
/// concurrent updates process-wide so two in-flight writes can't interleave
/// their read and write legs.
public actor PreferencesWriter {
    /// Process-wide shared writer. All preference mutations must go through
    /// the same instance so the read-modify-write serialization actually
    /// covers them.
    public static let shared = PreferencesWriter()

    /// Tail of the serialization chain. Each update awaits the previous one
    /// (success or failure) before performing its read leg.
    private var tail: Task<Void, Never>?

    public init() {}

    /// Read-modify-write with the mutation computed from the *fresh* server
    /// state — RN's `updatePreferences(cb)`. Return `nil` from `makeMutation`
    /// to skip the write entirely (RN's `cb` returning `false`).
    public func update(
        network: any NetworkClient,
        _ makeMutation: @escaping @Sendable (GetPreferencesResponse) throws -> PreferencesMutation?
    ) async throws {
        let previous = tail
        let work = Task { () throws -> Void in
            await previous?.value
            let current: GetPreferencesResponse = try await network.get(
                lexicon: "app.bsky.actor.getPreferences", params: [:]
            )
            guard let mutation = try makeMutation(current) else { return }
            let body = PutPreferencesRequest(
                merging: current.rawPreferences, applying: mutation
            )
            let _: EmptyResponse = try await network.post(
                lexicon: "app.bsky.actor.putPreferences", body: body
            )
        }
        tail = Task { try? await work.value }
        try await work.value
    }

    /// Convenience for mutations that don't depend on the current server
    /// state (the caller already loaded and mutated the affected preference).
    public func update(
        network: any NetworkClient, _ mutation: PreferencesMutation
    ) async throws {
        try await update(network: network) { _ in mutation }
    }
}
