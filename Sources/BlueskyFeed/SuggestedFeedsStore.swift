import Foundation
import OSLog
import Observation
import BlueskyCore
import BlueskyKit

nonisolated private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "co.sstools.Bluesky",
    category: "SuggestedFeedsStore"
)

// MARK: - SuggestedFeedsStoring

/// Backing store for the My Feeds screen's "Discover" section and its search
/// type-ahead. Exposes two arrays — `suggested` (curated, paged) and
/// `searchResults` (live, replaced on each new query) — so the screen can show
/// the discover list when the search box is empty and swap in matches as the
/// user types.
public protocol SuggestedFeedsStoring: AnyObject, Observable, Sendable {
    /// Curated suggested feeds from `app.bsky.feed.getSuggestedFeeds`.
    var suggested: [GeneratorView] { get }
    /// Live search results from `app.bsky.unspecced.getPopularFeedGenerators`.
    var searchResults: [GeneratorView] { get }
    /// Resolved `GeneratorView` for each saved-feed AT-URI the screen has asked
    /// about. Used to render real names/avatars/descriptions next to saved
    /// rows instead of the AT-URI fallback.
    var resolvedFeeds: [String: GeneratorView] { get }
    var isLoadingSuggested: Bool { get }
    var isSearching: Bool { get }
    var error: String? { get }

    func loadSuggested() async
    func search(query: String) async
    func clearSearch()
    /// Resolve a batch of saved-feed AT-URIs via `app.bsky.feed.getFeedGenerators`
    /// so the screen can show real names/avatars instead of AT-URI fallbacks.
    /// No-ops for already-resolved URIs.
    func resolve(uris: [String]) async
    /// Manually note that `view` is the resolved metadata for `uri`. Used by
    /// the My Feeds screen when adding a suggested feed to the saved list so
    /// the new row renders with the real name/avatar without a round trip.
    func noteResolved(_ view: GeneratorView, for uri: String)
}

// MARK: - SuggestedFeedsStore

@Observable
public final class SuggestedFeedsStore: SuggestedFeedsStoring {

    public private(set) var suggested: [GeneratorView] = []
    public private(set) var searchResults: [GeneratorView] = []
    public private(set) var resolvedFeeds: [String: GeneratorView] = [:]
    public private(set) var isLoadingSuggested = false
    public private(set) var isSearching = false
    public private(set) var error: String?

    private let network: any NetworkClient

    /// Tracks the most recent search request so a slow earlier response cannot
    /// overwrite a faster later one. Each call to `search` increments the id.
    @ObservationIgnored private var searchRequestID: UInt64 = 0

    public init(network: any NetworkClient) {
        self.network = network
    }

    // MARK: - Suggested (Discover)

    public func loadSuggested() async {
        guard suggested.isEmpty, !isLoadingSuggested else { return }
        isLoadingSuggested = true
        defer { isLoadingSuggested = false }
        do {
            let resp: GetSuggestedFeedsResponse = try await network.get(
                lexicon: "app.bsky.feed.getSuggestedFeeds",
                params: ["limit": "20"]
            )
            suggested = resp.feeds
        } catch {
            logger.error("loadSuggested failed: \(error, privacy: .public)")
            self.error = error.localizedDescription
        }
    }

    // MARK: - Search

    public func search(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            clearSearch()
            return
        }
        searchRequestID &+= 1
        let id = searchRequestID
        isSearching = true
        defer {
            // Only clear isSearching if no newer request has started.
            if id == searchRequestID { isSearching = false }
        }
        do {
            let resp: GetSuggestedFeedsResponse = try await network.get(
                lexicon: "app.bsky.unspecced.getPopularFeedGenerators",
                params: ["limit": "10", "query": trimmed]
            )
            // Discard if a newer query has already been issued.
            guard id == searchRequestID else { return }
            searchResults = resp.feeds
        } catch {
            logger.error("search feeds failed: \(error, privacy: .public)")
            guard id == searchRequestID else { return }
            self.error = error.localizedDescription
            searchResults = []
        }
    }

    public func clearSearch() {
        searchRequestID &+= 1
        searchResults = []
        isSearching = false
    }

    public func noteResolved(_ view: GeneratorView, for uri: String) {
        resolvedFeeds[uri] = view
    }

    // MARK: - Resolution

    public func resolve(uris: [String]) async {
        // Only fetch the URIs we don't already have, and only AT-URIs that
        // actually point at a feed generator (skip "following", lists, etc.).
        let needed = uris
            .filter { resolvedFeeds[$0] == nil }
            .filter { $0.contains("app.bsky.feed.generator") }
        guard !needed.isEmpty else { return }
        // The shared `NetworkClient.get` takes a `[String: String]` so it
        // can't encode repeated `feeds=` query items. Issue one
        // `getFeedGenerator` (singular) call per URI instead — the typical
        // saved-feeds list is small (<10) and the calls run in parallel via
        // `withTaskGroup`. If a multi-URI helper is added to `NetworkClient`
        // later, swap this loop for `app.bsky.feed.getFeedGenerators`.
        let net = network
        await withTaskGroup(of: (String, GeneratorView?).self) { group in
            for uri in needed {
                group.addTask {
                    do {
                        let resp: GetFeedGeneratorResponse = try await net.get(
                            lexicon: "app.bsky.feed.getFeedGenerator",
                            params: ["feed": uri]
                        )
                        return (uri, resp.view)
                    } catch {
                        logger.warning(
                            "resolve feed \(uri, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
                        )
                        return (uri, nil)
                    }
                }
            }
            for await (uri, view) in group {
                if let view { resolvedFeeds[uri] = view }
            }
        }
    }
}
