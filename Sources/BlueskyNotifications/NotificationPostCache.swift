import Foundation
import OSLog
import Observation
import BlueskyCore
import BlueskyKit

nonisolated private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "co.sstools.Bluesky",
    category: "NotificationPostCache"
)

// MARK: - NotificationPostCache

/// In-memory cache of `PostView` records keyed by AT-URI, used to render
/// inline post-text previews on notification rows (#0079).
///
/// Notifications come back from `app.bsky.notification.listNotifications`
/// without the underlying post body, so the screen has to hydrate each
/// row by calling `app.bsky.feed.getPosts(uris:)`. Holding the resolved
/// posts in this cache means subsequent render passes are free, and
/// re-fetching the same notification (refresh, switching filters) doesn't
/// retrigger the network.
///
/// `getPosts(uris: [...])` is the right server-side primitive (one call
/// hydrates up to 25 URIs), but our shared `NetworkClient.get` signature
/// is `[String: String]` — it can't carry repeated query keys. Until the
/// `NetworkClient` protocol is widened, we issue per-URI `getPosts` calls
/// in parallel via `withTaskGroup` (same fallback `SuggestedFeedsStore`
/// uses for `getFeedGenerator`). Each call resolves a single URI; the
/// fan-out is gated on the typical first-page size (50 notifications,
/// at most ~25 unique post URIs after grouping likes/reposts on the same
/// subject).
@Observable
@MainActor
public final class NotificationPostCache {

    /// Posts that have been resolved, keyed by AT-URI raw value.
    public private(set) var posts: [String: PostView] = [:]
    /// URIs whose fetch is currently in flight. Used by the row to render a
    /// loading placeholder while the post is being hydrated.
    public private(set) var inFlight: Set<String> = []
    /// URIs we have already attempted but for which `getPosts` returned no
    /// entry (deleted, blocked, etc.). Tracked separately so we don't render
    /// a perpetual placeholder.
    public private(set) var missing: Set<String> = []

    private let network: any NetworkClient

    public init(network: any NetworkClient) {
        self.network = network
    }

    // MARK: - Lookup

    public func post(for uri: ATURI) -> PostView? {
        posts[uri.rawValue]
    }

    /// `true` while a fetch for `uri` is outstanding *and* we don't yet have
    /// a cached entry. Drives the row's loading state.
    public func isLoading(uri: ATURI) -> Bool {
        guard posts[uri.rawValue] == nil else { return false }
        return inFlight.contains(uri.rawValue)
    }

    /// `true` once the fetch has completed but no post came back — the row
    /// should render without a preview rather than spinning forever.
    public func isMissing(uri: ATURI) -> Bool {
        missing.contains(uri.rawValue)
    }

    // MARK: - Hydration

    /// Fetches and caches `PostView` records for any `uris` not already
    /// cached or in flight.
    ///
    /// Per-URI parallel fan-out via `withTaskGroup`: see the type-level
    /// comment for the rationale (`NetworkClient.get` can't carry repeated
    /// query items, so we fall back to one-URI-at-a-time `getPosts` calls).
    /// The `inFlight` set is updated up-front so concurrent callers don't
    /// stampede the same URIs.
    public func hydrate(uris: [ATURI]) async {
        // Filter to URIs we haven't already resolved or attempted.
        let needed = uris.filter { uri in
            let raw = uri.rawValue
            return posts[raw] == nil
                && !inFlight.contains(raw)
                && !missing.contains(raw)
        }
        guard !needed.isEmpty else { return }

        // Mark URIs in flight so concurrent `hydrate` calls (e.g.
        // `loadInitial` followed by `loadMore`) don't refetch.
        for uri in needed { inFlight.insert(uri.rawValue) }
        defer {
            for uri in needed { inFlight.remove(uri.rawValue) }
        }

        let net = network
        await withTaskGroup(of: (String, PostView?).self) { group in
            for uri in needed {
                group.addTask { [uri] in
                    do {
                        let resp: GetPostsResponse = try await net.get(
                            lexicon: "app.bsky.feed.getPosts",
                            params: ["uris": uri.rawValue]
                        )
                        // The endpoint returns posts keyed by their own uri,
                        // not necessarily ours. Match strictly to be safe.
                        let match = resp.posts.first(where: { $0.uri == uri })
                        return (uri.rawValue, match)
                    } catch {
                        logger.warning(
                            "getPosts failed for \(uri.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)"
                        )
                        return (uri.rawValue, nil)
                    }
                }
            }
            for await (raw, view) in group {
                if let view {
                    posts[raw] = view
                } else {
                    // Don't retry a URI that came back empty — rows render
                    // without a preview rather than a perpetual spinner.
                    missing.insert(raw)
                }
            }
        }
    }
}
