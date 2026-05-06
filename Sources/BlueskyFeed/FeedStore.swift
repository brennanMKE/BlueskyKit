import Foundation
import OSLog
import Observation
import BlueskyCore
import BlueskyKit

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "co.sstools.Bluesky", category: "FeedStore")

private let cacheTTL: TimeInterval = 60

/// How long a `PostView` snapshot is considered "fresh enough" to base a
/// like/repost toggle decision on without re-checking the server. Beyond this
/// window the store re-fetches the post via `app.bsky.feed.getPosts` before
/// performing the toggle, so actions taken on stale state (e.g. after liking
/// from another device) operate against the actual current viewer state. See
/// issue #0041.
private let viewerStateFreshnessWindow: TimeInterval = 5

/// How long after a successful create-record (like or repost) we keep the
/// confirmed AT-URI cached in `pendingLikeURIs`/`pendingRepostURIs`. During
/// this window, any feed fetch or `freshenedPost` call that gets a response
/// from the AT Protocol indexer where viewer state is missing (the indexer
/// is lagging behind our just-written record) will be patched to show the
/// confirmed state instead of reverting. Issue #0053.
private let pendingURICleanupWindow: TimeInterval = 30

// MARK: - FeedStoring

public protocol FeedStoring: AnyObject, Observable, Sendable {
    var posts: [FeedViewPost] { get }
    var isLoading: Bool { get }
    var errorMessage: String? { get }

    func loadInitial(selection: FeedSelection) async
    func loadMore(selection: FeedSelection) async
    func refresh(selection: FeedSelection) async
    /// Toggle the viewer's like state on `post`. Refreshes the post's viewer
    /// state from the server first if the cached snapshot is stale, so the
    /// resulting like/unlike operates on the actual current state. See
    /// issue #0041.
    func toggleLike(post: PostView) async
    /// Toggle the viewer's repost state on `post`. Same staleness handling as
    /// `toggleLike`.
    func toggleRepost(post: PostView) async
    func like(post: PostView) async
    func unlike(post: PostView) async
    func repost(post: PostView) async
    func unrepost(post: PostView) async
    func bookmark(post: PostView) async
    func unbookmark(post: PostView) async
}

// MARK: - FeedStore

@Observable
public final class FeedStore: FeedStoring {

    public private(set) var posts: [FeedViewPost] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    private var cursor: String?
    private var hasMore = true
    private var currentSelection: FeedSelection?

    /// Post URIs whose like state is currently being mutated (like or unlike in-flight).
    /// Used both as a double-tap guard and to re-apply viewer state if a background
    /// refresh replaces the posts array before the API call completes.
    private var likeInFlight: Set<ATURI> = []
    /// Post URIs whose repost state is currently being mutated.
    private var repostInFlight: Set<ATURI> = []
    /// Post URIs whose bookmark state is currently being mutated.
    private var bookmarkInFlight: Set<ATURI> = []
    /// Confirmed like URI for each post that has a completed-but-not-yet-indexed like.
    /// Keyed by post URI; value is the server-returned like AT-URI.
    private var pendingLikeURIs: [ATURI: ATURI] = [:]
    /// Same concept for repost operations.
    private var pendingRepostURIs: [ATURI: ATURI] = [:]

    /// Wall-clock timestamp (`Date`) at which each post's viewer state was last
    /// fetched from the server. Used to decide whether a like/repost toggle
    /// can rely on the cached `viewer` snapshot, or whether the post should be
    /// re-fetched first via `app.bsky.feed.getPosts`. Issue #0041.
    @ObservationIgnored private var lastViewerStateCheck: [ATURI: Date] = [:]

    /// Non-observable flag used to prevent two concurrent `loadInitial` calls from
    /// both passing the guard. Using `@ObservationIgnored` means setting this flag
    /// does NOT trigger `@Observable` updates, so SwiftUI never re-renders (and
    /// cancels the active `.task`) as a side-effect of claiming the slot.
    @ObservationIgnored private var isInitialLoadInFlight = false

    private let network: any NetworkClient
    private let accountStore: any AccountStore
    private let cache: any CacheStore

    public init(
        network: any NetworkClient,
        accountStore: any AccountStore,
        cache: any CacheStore
    ) {
        self.network = network
        self.accountStore = accountStore
        self.cache = cache
    }

    // MARK: - Loading

    public func loadInitial(selection: FeedSelection) async {
        logger.debug("loadInitial called, isLoading=\(self.isLoading, privacy: .public), posts=\(self.posts.count, privacy: .public)")
        // Use @ObservationIgnored flag so claiming the slot does NOT trigger an
        // @Observable update — that would cause SwiftUI to re-render and cancel
        // the active .task before the network call completes.
        guard !isInitialLoadInFlight, posts.isEmpty else {
            logger.debug("loadInitial guard failed — returning early (inFlight=\(self.isInitialLoadInFlight, privacy: .public), posts=\(self.posts.count, privacy: .public))")
            return
        }
        isInitialLoadInFlight = true
        defer { isInitialLoadInFlight = false }
        currentSelection = selection
        // Serve stale cache immediately so the UI has content before the network responds.
        do {
            if let cached = try await cache.fetch([FeedViewPost].self, for: cacheKey(selection)) {
                logger.debug("serving \(cached.value.count, privacy: .public) cached posts (expired=\(cached.isExpired, privacy: .public))")
                posts = cached.value
            } else {
                logger.debug("no cached posts found for key=\(self.cacheKey(selection), privacy: .public)")
            }
        } catch {
            logger.error("cache fetch error for key=\(self.cacheKey(selection), privacy: .public): \(error, privacy: .public)")
        }
        await fetch(selection: selection, reset: true)
    }

    public func loadMore(selection: FeedSelection) async {
        guard !isLoading, hasMore else { return }
        await fetch(selection: selection, reset: false)
    }

    public func refresh(selection: FeedSelection) async {
        await fetch(selection: selection, reset: true)
    }

    private func fetch(selection: FeedSelection, reset: Bool) async {
        logger.debug("fetch start, reset=\(reset, privacy: .public)")
        isLoading = true
        defer { isLoading = false }
        // Snapshot current posts so we can restore them if a reset-fetch fails (offline fallback).
        let postsBeforeReset = reset ? posts : []
        if reset { cursor = nil; hasMore = true }
        errorMessage = nil
        do {
            var params: [String: String] = ["limit": "50"]
            if let cursor { params["cursor"] = cursor }
            let response: FeedResponse
            switch selection {
            case .timeline:
                logger.debug("calling getTimeline")
                response = try await network.get(lexicon: "app.bsky.feed.getTimeline", params: params)
            case .feed(let uri):
                logger.debug("calling getFeed uri=\(uri, privacy: .public)")
                params["feed"] = uri
                response = try await network.get(lexicon: "app.bsky.feed.getFeed", params: params)
            }
            logger.debug("fetch succeeded, count=\(response.feed.count, privacy: .public), cursor=\(response.cursor ?? "nil", privacy: .public)")
            cursor = response.cursor
            hasMore = response.cursor != nil
            // Mark every post in this response as having a fresh viewer-state
            // snapshot, so a like/repost tap immediately afterward does not
            // trigger an unnecessary `getPosts` round-trip.
            let now = Date()
            for item in response.feed { lastViewerStateCheck[item.post.uri] = now }
            if reset {
                // Re-apply any viewer state that is still in-flight so that a background
                // refresh does not silently revert an optimistic like/repost that hasn't
                // been confirmed yet (or has been confirmed but the server hasn't indexed
                // it into this feed response yet). Issue #0053.
                let hasPendingLikes = !likeInFlight.isEmpty || !pendingLikeURIs.isEmpty
                let hasPendingReposts = !repostInFlight.isEmpty || !pendingRepostURIs.isEmpty
                if hasPendingLikes || hasPendingReposts {
                    posts = response.feed.map { item in
                        var pv = item.post
                        // Like state. If the indexer has now caught up and the server
                        // is reporting the like, drop the pending entry. Otherwise
                        // prefer the confirmed URI, then the optimistic placeholder.
                        if let confirmedLikeURI = pendingLikeURIs[pv.uri] {
                            if pv.viewer?.like != nil {
                                pendingLikeURIs.removeValue(forKey: pv.uri)
                            } else {
                                pv = pv.withLike(confirmedLikeURI)
                            }
                        } else if likeInFlight.contains(pv.uri), pv.viewer?.like == nil {
                            pv = pv.withLike(ATURI(rawValue: "pending://like"))
                        }
                        // Repost state — same handling.
                        if let confirmedRepostURI = pendingRepostURIs[pv.uri] {
                            if pv.viewer?.repost != nil {
                                pendingRepostURIs.removeValue(forKey: pv.uri)
                            } else {
                                pv = pv.withRepost(confirmedRepostURI)
                            }
                        } else if repostInFlight.contains(pv.uri), pv.viewer?.repost == nil {
                            pv = pv.withRepost(ATURI(rawValue: "pending://repost"))
                        }
                        return FeedViewPost(post: pv, reply: item.reply, reason: item.reason)
                    }
                } else {
                    posts = response.feed
                }
            } else {
                posts.append(contentsOf: response.feed)
            }
            // Cache first page only
            if reset {
                do {
                    try await cache.store(posts, for: cacheKey(selection), ttl: cacheTTL)
                    logger.debug("cached \(self.posts.count, privacy: .public) posts for key=\(self.cacheKey(selection), privacy: .public)")
                } catch {
                    logger.error("cache store failed: \(error, privacy: .public)")
                }
            }
        } catch {
            logger.error("fetch error: \(error, privacy: .public)")
            if reset, !postsBeforeReset.isEmpty {
                // Restore cached snapshot so offline users see stale content rather than
                // a blank feed. Clear errorMessage so the UI shows the cached posts.
                logger.debug("network failed; restoring \(postsBeforeReset.count, privacy: .public) cached posts")
                posts = postsBeforeReset
                errorMessage = nil
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func cacheKey(_ selection: FeedSelection) -> String {
        switch selection {
        case .timeline:    "feed.timeline"
        case .feed(let u): "feed.\(u)"
        }
    }

    // MARK: - Freshness

    /// Returns the current `PostView` for `uri`, re-fetching from the server
    /// (`app.bsky.feed.getPosts`) when the local viewer-state snapshot is
    /// older than `viewerStateFreshnessWindow`. The refreshed `PostView` is
    /// also written back into `posts` so the UI reflects any server-side
    /// state that changed (e.g. a like added from another device).
    ///
    /// If a network error occurs during refresh, the local snapshot is
    /// returned as a fallback rather than failing the toggle outright.
    ///
    /// Server responses are overlaid with any in-flight or recently-confirmed
    /// optimistic viewer state for `uri` so that the AT Protocol indexer's
    /// lag (a like/repost can take several seconds to appear in `getPosts`)
    /// does not silently revert state we already know is correct. Issue #0053.
    private func freshenedPost(for uri: ATURI) async -> PostView? {
        let cachedAt = lastViewerStateCheck[uri]
        let isFresh = cachedAt.map { Date().timeIntervalSince($0) < viewerStateFreshnessWindow } ?? false
        let local = posts.first(where: { $0.post.uri == uri })?.post
        if isFresh { return local }
        do {
            let response: GetPostsResponse = try await network.get(
                lexicon: "app.bsky.feed.getPosts",
                params: ["uris": uri.rawValue]
            )
            guard let serverFresh = response.posts.first(where: { $0.uri == uri }) else {
                logger.debug("getPosts returned no entry for \(uri.rawValue, privacy: .public); falling back to local snapshot")
                return local
            }
            lastViewerStateCheck[uri] = Date()
            let merged = overlayPendingState(on: serverFresh)
            updatePost(uri: uri) { _ in merged }
            logger.debug("refreshed viewer state for \(uri.rawValue, privacy: .public): like=\(merged.viewer?.like?.rawValue ?? "nil", privacy: .public), repost=\(merged.viewer?.repost?.rawValue ?? "nil", privacy: .public)")
            return merged
        } catch {
            logger.error("getPosts refresh failed for \(uri.rawValue, privacy: .public): \(error, privacy: .public); using local snapshot")
            return local
        }
    }

    /// Overlays any in-flight or recently-confirmed optimistic viewer state on
    /// top of a server response, so a server-side response that hasn't yet
    /// reflected a freshly created like/repost record does not revert the UI.
    /// Issue #0053.
    ///
    /// - If we have a confirmed `pendingLikeURIs` entry and the server now
    ///   reports the like, drop the pending entry (indexer caught up).
    /// - If we have a confirmed entry but the server still reports no like,
    ///   keep the confirmed URI (indexer is lagging).
    /// - If a like is still in-flight (slot held but not yet confirmed) and
    ///   the local copy already shows the optimistic pending state, preserve
    ///   it rather than letting a server response briefly clear the heart.
    /// - Same handling for repost.
    private func overlayPendingState(on serverPost: PostView) -> PostView {
        var p = serverPost
        let localLike = posts.first(where: { $0.post.uri == p.uri })?.post.viewer?.like
        let localRepost = posts.first(where: { $0.post.uri == p.uri })?.post.viewer?.repost
        if let confirmed = pendingLikeURIs[p.uri] {
            if p.viewer?.like != nil {
                pendingLikeURIs.removeValue(forKey: p.uri)
            } else {
                p = p.withLike(confirmed)
            }
        } else if likeInFlight.contains(p.uri),
                  p.viewer?.like == nil,
                  let localLike {
            // Local already shows liked (optimistic pending) — keep it.
            p = p.withLike(localLike)
        }
        if let confirmed = pendingRepostURIs[p.uri] {
            if p.viewer?.repost != nil {
                pendingRepostURIs.removeValue(forKey: p.uri)
            } else {
                p = p.withRepost(confirmed)
            }
        } else if repostInFlight.contains(p.uri),
                  p.viewer?.repost == nil,
                  let localRepost {
            p = p.withRepost(localRepost)
        }
        return p
    }

    // MARK: - Toggles

    public func toggleLike(post: PostView) async {
        // Claim the in-flight slot up front so a stale-state refresh that races
        // with a second tap can't slip through. The actual create/delete is
        // dispatched to `like`/`unlike` which see the slot already claimed and
        // perform only their own work via the `skipInFlightCheck` path.
        guard likeInFlight.insert(post.uri).inserted else {
            logger.debug("toggleLike ignored — already in-flight for \(post.uri.rawValue, privacy: .public)")
            return
        }
        defer { likeInFlight.remove(post.uri) }
        let current = await freshenedPost(for: post.uri) ?? post
        if current.viewer?.like != nil {
            await performUnlike(post: current)
        } else {
            await performLike(post: current)
        }
    }

    public func toggleRepost(post: PostView) async {
        guard repostInFlight.insert(post.uri).inserted else {
            logger.debug("toggleRepost ignored — already in-flight for \(post.uri.rawValue, privacy: .public)")
            return
        }
        defer { repostInFlight.remove(post.uri) }
        let current = await freshenedPost(for: post.uri) ?? post
        if current.viewer?.repost != nil {
            await performUnrepost(post: current)
        } else {
            await performRepost(post: current)
        }
    }

    // MARK: - Interactions

    public func like(post: PostView) async {
        // Double-tap guard: claim the slot synchronously (before any await) so a second
        // concurrent call that arrives before loadCurrentDID returns is also blocked.
        guard likeInFlight.insert(post.uri).inserted else {
            logger.debug("like ignored — already in-flight for \(post.uri.rawValue, privacy: .public)")
            return
        }
        defer { likeInFlight.remove(post.uri) }
        await performLike(post: post)
    }

    public func unlike(post: PostView) async {
        guard post.viewer?.like != nil else { return }
        // Claim the slot synchronously before any await.
        guard likeInFlight.insert(post.uri).inserted else {
            logger.debug("unlike ignored — already in-flight for \(post.uri.rawValue, privacy: .public)")
            return
        }
        defer { likeInFlight.remove(post.uri) }
        await performUnlike(post: post)
    }

    public func repost(post: PostView) async {
        // Claim the slot synchronously before any await.
        guard repostInFlight.insert(post.uri).inserted else {
            logger.debug("repost ignored — already in-flight for \(post.uri.rawValue, privacy: .public)")
            return
        }
        defer { repostInFlight.remove(post.uri) }
        await performRepost(post: post)
    }

    public func unrepost(post: PostView) async {
        guard post.viewer?.repost != nil else { return }
        // Claim the slot synchronously before any await.
        guard repostInFlight.insert(post.uri).inserted else {
            logger.debug("unrepost ignored — already in-flight for \(post.uri.rawValue, privacy: .public)")
            return
        }
        defer { repostInFlight.remove(post.uri) }
        await performUnrepost(post: post)
    }

    // MARK: - Inner like/repost work (caller owns the in-flight slot)

    /// Create the like record. Caller must already hold `likeInFlight` for this URI.
    private func performLike(post: PostView) async {
        guard let did = await loadCurrentDID() else { return }
        // Re-check viewer state from the live posts array — the passed-in post may be stale
        // if a feed refresh ran during the loadCurrentDID await above. If the local snapshot
        // is itself stale, freshen it from the server so we don't double-like a post that
        // was liked from another device. Issue #0041.
        let livePost = await freshenedPost(for: post.uri) ?? post
        guard livePost.viewer?.like == nil else {
            logger.debug("like ignored — post already liked: \(post.uri.rawValue, privacy: .public)")
            return
        }
        updatePost(uri: post.uri) { $0.withLike(ATURI(rawValue: "pending://like")) }
        do {
            let req = CreateRecordRequest(
                repo: did.rawValue,
                collection: "app.bsky.feed.like",
                record: LikeRecord(subject: PostRef(uri: post.uri, cid: post.cid))
            )
            let resp: CreateRecordResponse = try await network.post(
                lexicon: "com.atproto.repo.createRecord", body: req
            )
            logger.debug("like succeeded, likeURI=\(resp.uri.rawValue, privacy: .public)")
            // Store the confirmed URI so that any subsequent feed refresh or
            // freshenedPost can re-apply it rather than reverting while the
            // AT Protocol indexer catches up. Issue #0053. Cleared by the
            // next fetch/freshenedPost that observes the server returning
            // the like in viewer state, OR after a safety timeout below.
            pendingLikeURIs[post.uri] = resp.uri
            updatePost(uri: post.uri) { $0.withLike(resp.uri) }
            // Schedule a safety-net cleanup so the entry doesn't linger
            // forever if no further fetch ever happens.
            schedulePendingLikeCleanup(uri: post.uri, confirmed: resp.uri)
        } catch {
            logger.error("like failed for \(post.uri.rawValue, privacy: .public): \(error, privacy: .public)")
            // The create failed — clear any confirmed URI in case a previous
            // attempt left one behind, and revert the optimistic update.
            pendingLikeURIs.removeValue(forKey: post.uri)
            updatePost(uri: post.uri) { $0.withLike(nil) }
        }
    }

    /// Delete the like record. Caller must already hold `likeInFlight` for this URI.
    private func performUnlike(post: PostView) async {
        // Freshen viewer state so we don't try to delete a like record that
        // was already removed from another device. Issue #0041.
        let livePost = await freshenedPost(for: post.uri) ?? post
        guard let likeURI = livePost.viewer?.like else {
            logger.debug("unlike skipped — server reports no active like for \(post.uri.rawValue, privacy: .public)")
            // Make sure local state matches server.
            pendingLikeURIs.removeValue(forKey: post.uri)
            updatePost(uri: post.uri) { $0.withLike(nil) }
            return
        }
        guard let did = await loadCurrentDID(),
              let rkey = likeURI.rkey else { return }
        // Drop any cached confirmed-like entry; we are explicitly removing the
        // like and don't want a deferred cleanup to re-apply it. Issue #0053.
        pendingLikeURIs.removeValue(forKey: post.uri)
        updatePost(uri: post.uri) { $0.withLike(nil) }
        do {
            let req = DeleteRecordRequest(repo: did.rawValue, collection: "app.bsky.feed.like", rkey: rkey)
            let _: EmptyResponse = try await network.post(lexicon: "com.atproto.repo.deleteRecord", body: req)
            logger.debug("unlike succeeded for \(post.uri.rawValue, privacy: .public)")
        } catch {
            logger.error("unlike failed for \(post.uri.rawValue, privacy: .public): \(error, privacy: .public)")
            updatePost(uri: post.uri) { $0.withLike(likeURI) }
        }
    }

    /// Create the repost record. Caller must already hold `repostInFlight` for this URI.
    private func performRepost(post: PostView) async {
        guard let did = await loadCurrentDID() else { return }
        // Freshen the viewer state if the cached snapshot is stale so we don't
        // re-repost a post that was already reposted from another device.
        // Issue #0041.
        let livePost = await freshenedPost(for: post.uri) ?? post
        guard livePost.viewer?.repost == nil else {
            logger.debug("repost ignored — post already reposted: \(post.uri.rawValue, privacy: .public)")
            return
        }
        updatePost(uri: post.uri) { $0.withRepost(ATURI(rawValue: "pending://repost")) }
        do {
            let req = CreateRecordRequest(
                repo: did.rawValue,
                collection: "app.bsky.feed.repost",
                record: RepostRecord(subject: PostRef(uri: post.uri, cid: post.cid))
            )
            let resp: CreateRecordResponse = try await network.post(
                lexicon: "com.atproto.repo.createRecord", body: req
            )
            logger.debug("repost succeeded, repostURI=\(resp.uri.rawValue, privacy: .public)")
            // Hold the confirmed URI so subsequent fetches/freshenedPost can
            // re-apply it while the indexer catches up. Issue #0053.
            pendingRepostURIs[post.uri] = resp.uri
            updatePost(uri: post.uri) { $0.withRepost(resp.uri) }
            schedulePendingRepostCleanup(uri: post.uri, confirmed: resp.uri)
        } catch {
            logger.error("repost failed for \(post.uri.rawValue, privacy: .public): \(error, privacy: .public)")
            pendingRepostURIs.removeValue(forKey: post.uri)
            updatePost(uri: post.uri) { $0.withRepost(nil) }
        }
    }

    /// Delete the repost record. Caller must already hold `repostInFlight` for this URI.
    private func performUnrepost(post: PostView) async {
        // Freshen viewer state so we don't try to delete a repost record that
        // was already removed from another device. Issue #0041.
        let livePost = await freshenedPost(for: post.uri) ?? post
        guard let repostURI = livePost.viewer?.repost else {
            logger.debug("unrepost skipped — server reports no active repost for \(post.uri.rawValue, privacy: .public)")
            pendingRepostURIs.removeValue(forKey: post.uri)
            updatePost(uri: post.uri) { $0.withRepost(nil) }
            return
        }
        guard let did = await loadCurrentDID(),
              let rkey = repostURI.rkey else { return }
        // Drop any cached confirmed-repost entry; we are explicitly removing
        // the repost. Issue #0053.
        pendingRepostURIs.removeValue(forKey: post.uri)
        updatePost(uri: post.uri) { $0.withRepost(nil) }
        do {
            let req = DeleteRecordRequest(repo: did.rawValue, collection: "app.bsky.feed.repost", rkey: rkey)
            let _: EmptyResponse = try await network.post(lexicon: "com.atproto.repo.deleteRecord", body: req)
            logger.debug("unrepost succeeded for \(post.uri.rawValue, privacy: .public)")
        } catch {
            logger.error("unrepost failed for \(post.uri.rawValue, privacy: .public): \(error, privacy: .public)")
            updatePost(uri: post.uri) { $0.withRepost(repostURI) }
        }
    }

    public func bookmark(post: PostView) async {
        guard bookmarkInFlight.insert(post.uri).inserted else {
            logger.debug("bookmark ignored — already in-flight for \(post.uri.rawValue, privacy: .public)")
            return
        }
        defer { bookmarkInFlight.remove(post.uri) }
        let livePost = posts.first(where: { $0.post.uri == post.uri })?.post ?? post
        guard livePost.viewer?.bookmarked != true else {
            logger.debug("bookmark ignored — post already bookmarked: \(post.uri.rawValue, privacy: .public)")
            return
        }
        updatePost(uri: post.uri) { $0.withBookmarked(true) }
        do {
            let _: EmptyResponse = try await network.post(
                lexicon: "app.bsky.bookmark.createBookmark",
                body: CreateBookmarkRequest(post: post)
            )
            logger.debug("bookmark succeeded for \(post.uri.rawValue, privacy: .public)")
        } catch {
            logger.error("bookmark failed for \(post.uri.rawValue, privacy: .public): \(error, privacy: .public)")
            updatePost(uri: post.uri) { $0.withBookmarked(false) }
        }
    }

    public func unbookmark(post: PostView) async {
        guard bookmarkInFlight.insert(post.uri).inserted else {
            logger.debug("unbookmark ignored — already in-flight for \(post.uri.rawValue, privacy: .public)")
            return
        }
        defer { bookmarkInFlight.remove(post.uri) }
        updatePost(uri: post.uri) { $0.withBookmarked(false) }
        do {
            // The deleteBookmark lexicon takes the post's own AT-URI (not a bookmark record URI).
            let _: EmptyResponse = try await network.post(
                lexicon: "app.bsky.bookmark.deleteBookmark",
                body: DeleteBookmarkRequest(bookmarkURI: post.uri)
            )
            logger.debug("unbookmark succeeded for \(post.uri.rawValue, privacy: .public)")
        } catch {
            logger.error("unbookmark failed for \(post.uri.rawValue, privacy: .public): \(error, privacy: .public)")
            updatePost(uri: post.uri) { $0.withBookmarked(true) }
        }
    }

    // MARK: - Helpers

    private func loadCurrentDID() async -> DID? {
        do {
            return try await accountStore.loadCurrentDID()
        } catch {
            logger.error("loadCurrentDID failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func updatePost(uri: ATURI, transform: (PostView) -> PostView) {
        guard let idx = posts.firstIndex(where: { $0.post.uri == uri }) else { return }
        let old = posts[idx]
        posts[idx] = FeedViewPost(post: transform(old.post), reply: old.reply, reason: old.reason)
    }

    /// Safety-net cleanup for `pendingLikeURIs[uri]`. The indexer normally
    /// catches up within a few seconds; after the cleanup window we drop the
    /// entry only if it still matches the URI we wrote (i.e. nothing else has
    /// replaced it in the meantime, e.g. a quick unlike). Issue #0053.
    private func schedulePendingLikeCleanup(uri: ATURI, confirmed: ATURI) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(pendingURICleanupWindow))
            guard let self else { return }
            if self.pendingLikeURIs[uri] == confirmed {
                self.pendingLikeURIs.removeValue(forKey: uri)
            }
        }
    }

    /// Same as `schedulePendingLikeCleanup` for repost.
    private func schedulePendingRepostCleanup(uri: ATURI, confirmed: ATURI) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(pendingURICleanupWindow))
            guard let self else { return }
            if self.pendingRepostURIs[uri] == confirmed {
                self.pendingRepostURIs.removeValue(forKey: uri)
            }
        }
    }
}
