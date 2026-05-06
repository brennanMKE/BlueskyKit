import Foundation
import OSLog
import Observation
import BlueskyCore
import BlueskyKit

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "co.sstools.Bluesky", category: "SavedFeedsStore")

private let cacheTTL: TimeInterval = 300

// MARK: - SavedFeedsStoring

public protocol SavedFeedsStoring: AnyObject, Observable, Sendable {
    var feeds: [SavedFeed] { get set }
    var isLoading: Bool { get }
    var isSaving: Bool { get }
    var error: String? { get }

    func load() async
    func save() async
}

// MARK: - SavedFeedsStore

@Observable
public final class SavedFeedsStore: SavedFeedsStoring {

    public var feeds: [SavedFeed] = []
    public private(set) var isLoading = false
    public private(set) var isSaving = false
    public private(set) var error: String?

    private let network: any NetworkClient
    private let cache: any CacheStore

    public init(network: any NetworkClient, cache: any CacheStore) {
        self.network = network
        self.cache = cache
    }

    public func load() async {
        do {
            if let cached = try await cache.fetch([SavedFeed].self, for: "savedFeeds") {
                feeds = cached.value
            }
        } catch {
            // Cache read failure is not fatal; the network fetch below will repopulate.
            logger.debug("savedFeeds cache fetch failed: \(error.localizedDescription, privacy: .public)")
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let prefs: GetPreferencesResponse = try await network.get(
                lexicon: "app.bsky.actor.getPreferences", params: [:]
            )
            feeds = prefs.savedFeeds
            do {
                try await cache.store(feeds, for: "savedFeeds", ttl: cacheTTL)
            } catch {
                logger.warning("savedFeeds cache store failed: \(error.localizedDescription, privacy: .public)")
            }
        } catch {
            logger.error("savedFeeds load error: \(error, privacy: .public)")
            self.error = error.localizedDescription
        }
    }

    public func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let _: EmptyResponse = try await network.post(
                lexicon: "app.bsky.actor.putPreferences",
                body: PutPreferencesRequest(savedFeeds: feeds)
            )
            do {
                try await cache.store(feeds, for: "savedFeeds", ttl: cacheTTL)
            } catch {
                logger.warning("savedFeeds cache store failed (post-save): \(error.localizedDescription, privacy: .public)")
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
