import Foundation
import Observation
import OSLog
import BlueskyCore
import BlueskyKit

private let wizardSearchLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "co.sstools.Bluesky",
    category: "StarterPackWizardSearch"
)

/// Lightweight search backing for the wizard's Profiles + Feeds steps.
///
/// Keeps three independent result sets so the steps can render their
/// "default" / "search results" lists without stepping on each other:
///
/// - `topActors`     — empty-query default for the Profiles step. Loaded
///                     from `app.bsky.actor.searchActors?q=*` (matches RN's
///                     `useActorSearch({query: '*'})`).
/// - `actorResults`  — debounced typeahead via
///                     `app.bsky.actor.searchActorsTypeahead`.
/// - `popularFeeds`  — empty-query default for the Feeds step. Loaded
///                     from `app.bsky.unspecced.getPopularFeedGenerators`
///                     with no query.
/// - `feedResults`   — query-driven popular feeds for the Feeds step.
@MainActor
@Observable
public final class StarterPackWizardSearchStore {

    public private(set) var topActors: [ProfileBasic] = []
    public private(set) var actorResults: [ProfileBasic] = []
    public private(set) var popularFeeds: [GeneratorView] = []
    public private(set) var feedResults: [GeneratorView] = []

    public private(set) var isLoadingTopActors = false
    public private(set) var isSearchingActors = false
    public private(set) var isLoadingFeeds = false
    public private(set) var isSearchingFeeds = false

    @ObservationIgnored private var actorSearchID: UInt64 = 0
    @ObservationIgnored private var feedSearchID: UInt64 = 0
    @ObservationIgnored private var actorTask: Task<Void, Never>?
    @ObservationIgnored private var feedTask: Task<Void, Never>?

    private let network: any NetworkClient

    public init(network: any NetworkClient) {
        self.network = network
    }

    // MARK: - Profiles

    /// Fetches the empty-query default list once. RN seeds the Profiles step
    /// with `searchActors?q=*` to surface "top followers" — we mirror that.
    public func loadTopActorsIfNeeded() async {
        guard topActors.isEmpty, !isLoadingTopActors else { return }
        isLoadingTopActors = true
        defer { isLoadingTopActors = false }
        do {
            let resp: SearchActorsResponse = try await network.get(
                lexicon: "app.bsky.actor.searchActors",
                params: ["q": "*", "limit": "30"]
            )
            // searchActors returns ProfileView; wizard cells render against
            // ProfileBasic so the same row works for typeahead too.
            topActors = resp.actors.map { profile in
                ProfileBasic(
                    did: profile.did,
                    handle: profile.handle,
                    displayName: profile.displayName,
                    avatar: profile.avatar,
                    labels: profile.labels,
                    verification: profile.verification
                )
            }
        } catch {
            wizardSearchLogger.error("loadTopActors failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Debounced actor typeahead (200 ms). Empty query clears results so the
    /// step falls back to `topActors`.
    public func searchActors(query: String) {
        actorTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            actorResults = []
            isSearchingActors = false
            return
        }
        actorSearchID &+= 1
        let id = actorSearchID
        let net = network
        actorTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled, let self else { return }
            self.isSearchingActors = true
            defer {
                if id == self.actorSearchID { self.isSearchingActors = false }
            }
            do {
                let resp: SearchActorsTypeaheadResponse = try await net.get(
                    lexicon: "app.bsky.actor.searchActorsTypeahead",
                    params: ["q": trimmed, "limit": "12"]
                )
                guard id == self.actorSearchID else { return }
                self.actorResults = resp.actors
            } catch {
                wizardSearchLogger.error("searchActors failed: \(error.localizedDescription, privacy: .public)")
                guard id == self.actorSearchID else { return }
                self.actorResults = []
            }
        }
    }

    // MARK: - Feeds

    /// Empty-query popular feeds default for the Feeds step. RN combines
    /// saved feeds + popular feeds; the wizard ports the popular-feed leg
    /// because saved-feed wiring would require importing the prefs store.
    public func loadPopularFeedsIfNeeded() async {
        guard popularFeeds.isEmpty, !isLoadingFeeds else { return }
        isLoadingFeeds = true
        defer { isLoadingFeeds = false }
        do {
            let resp: GetSuggestedFeedsResponse = try await network.get(
                lexicon: "app.bsky.unspecced.getPopularFeedGenerators",
                params: ["limit": "30"]
            )
            popularFeeds = resp.feeds
        } catch {
            wizardSearchLogger.error("loadPopularFeeds failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Debounced popular-feed search (300 ms — RN throttles at 500 ms but
    /// SwiftUI debounces feel snappier at 300).
    public func searchFeeds(query: String) {
        feedTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            feedResults = []
            isSearchingFeeds = false
            return
        }
        feedSearchID &+= 1
        let id = feedSearchID
        let net = network
        feedTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }
            self.isSearchingFeeds = true
            defer {
                if id == self.feedSearchID { self.isSearchingFeeds = false }
            }
            do {
                let resp: GetSuggestedFeedsResponse = try await net.get(
                    lexicon: "app.bsky.unspecced.getPopularFeedGenerators",
                    params: ["limit": "10", "query": trimmed]
                )
                guard id == self.feedSearchID else { return }
                self.feedResults = resp.feeds
            } catch {
                wizardSearchLogger.error("searchFeeds failed: \(error.localizedDescription, privacy: .public)")
                guard id == self.feedSearchID else { return }
                self.feedResults = []
            }
        }
    }
}
