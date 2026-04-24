import BlueskyCore
import Observation

/// The application's dependency container.
///
/// Assemble a `BlueskyEnvironment` at app launch by injecting concrete implementations
/// of each protocol, then pass it into the SwiftUI environment:
///
/// ```swift
/// @main struct BlueskyApp: App {
///     let env = BlueskyEnvironment(
///         session: LiveSessionManager(...),
///         accounts: KeychainAccountStore(),
///         preferences: UserDefaultsPreferencesStore(),
///         network: ATProtoClient(...),
///         cache: SwiftDataCacheStore(appGroupIdentifier: "group.app.bsky")
///     )
///
///     var body: some Scene {
///         WindowGroup { ContentView().environment(env) }
///     }
/// }
/// ```
@MainActor
@Observable
public final class BlueskyEnvironment {
    public let session: any SessionManaging
    public let accounts: any AccountStore
    public let preferences: any PreferencesStore
    public let network: any NetworkClient
    public let cache: any CacheStore

    public init(
        session: any SessionManaging,
        accounts: any AccountStore,
        preferences: any PreferencesStore,
        network: any NetworkClient,
        cache: any CacheStore
    ) {
        self.session = session
        self.accounts = accounts
        self.preferences = preferences
        self.network = network
        self.cache = cache
    }
}
