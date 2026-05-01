import Foundation
import OSLog
import Observation
import BlueskyCore
import BlueskyKit

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "co.sstools.Bluesky", category: "FeedStore")

private let cacheTTL: TimeInterval = 60

// MARK: - FeedStoring

public protocol FeedStoring: AnyObject, Observable, Sendable {
    var posts: [FeedViewPost] { get }
    var isLoading: Bool { get }
    var errorMessage: String? { get }

    func loadInitial(selection: FeedSelection) async
    func loadMore(selection: FeedSelection) async
    func refresh(selection: FeedSelection) async
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
            if reset {
                // Re-apply any viewer state that is still in-flight so that a background
                // refresh does not silently revert an optimistic like/repost that hasn't
                // been confirmed yet (or has been confirmed but the server hasn't indexed
                // it into this feed response yet).
                let hasPendingLikes = !likeInFlight.isEmpty || !pendingLikeURIs.isEmpty
                let hasPendingReposts = !repostInFlight.isEmpty || !pendingRepostURIs.isEmpty
                if hasPendingLikes || hasPendingReposts {
                    posts = response.feed.map { item in
                        var pv = item.post
                        // Prefer the server-confirmed URI; fall back to optimistic "pending://"
                        // for operations that haven't completed yet.
                        if let confirmedLikeURI = pendingLikeURIs[pv.uri] {
                            pv = pv.withLike(confirmedLikeURI)
                        } else if likeInFlight.contains(pv.uri) {
                            pv = pv.withLike(ATURI(rawValue: "pending://like"))
                        }
                        if let confirmedRepostURI = pendingRepostURIs[pv.uri] {
                            pv = pv.withRepost(confirmedRepostURI)
                        } else if repostInFlight.contains(pv.uri) {
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

    // MARK: - Interactions

    public func like(post: PostView) async {
        // Double-tap guard: claim the slot synchronously (before any await) so a second
        // concurrent call that arrives before loadCurrentDID returns is also blocked.
        guard likeInFlight.insert(post.uri).inserted else {
            logger.debug("like ignored — already in-flight for \(post.uri.rawValue, privacy: .public)")
            return
        }
        defer { likeInFlight.remove(post.uri) }
        guard let did = await loadCurrentDID() else { return }
        // Re-check viewer state from the live posts array — the passed-in post may be stale
        // if a feed refresh ran during the loadCurrentDID await above.
        let livePost = posts.first(where: { $0.post.uri == post.uri })?.post ?? post
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
            // Store the confirmed URI so that if a feed refresh fires before the server
            // has indexed this like, the refresh can re-apply it rather than reverting.
            pendingLikeURIs[post.uri] = resp.uri
            updatePost(uri: post.uri) { $0.withLike(resp.uri) }
        } catch {
            logger.error("like failed for \(post.uri.rawValue, privacy: .public): \(error, privacy: .public)")
            updatePost(uri: post.uri) { $0.withLike(nil) }
        }
        // Clear the confirmed URI now that the operation is settled — the next feed refresh
        // will include the server's authoritative viewer state.
        pendingLikeURIs.removeValue(forKey: post.uri)
        // defer removes likeInFlight entry.
    }

    public func unlike(post: PostView) async {
        guard let likeURI = post.viewer?.like else { return }
        // Claim the slot synchronously before any await.
        guard likeInFlight.insert(post.uri).inserted else {
            logger.debug("unlike ignored — already in-flight for \(post.uri.rawValue, privacy: .public)")
            return
        }
        defer { likeInFlight.remove(post.uri) }
        guard let did = await loadCurrentDID(),
              let rkey = likeURI.rkey else { return }
        updatePost(uri: post.uri) { $0.withLike(nil) }
        do {
            let req = DeleteRecordRequest(repo: did.rawValue, collection: "app.bsky.feed.like", rkey: rkey)
            let _: EmptyResponse = try await network.post(lexicon: "com.atproto.repo.deleteRecord", body: req)
            logger.debug("unlike succeeded for \(post.uri.rawValue, privacy: .public)")
        } catch {
            logger.error("unlike failed for \(post.uri.rawValue, privacy: .public): \(error, privacy: .public)")
            updatePost(uri: post.uri) { $0.withLike(likeURI) }
        }
        // defer removes likeInFlight entry.
    }

    public func repost(post: PostView) async {
        // Claim the slot synchronously before any await.
        guard repostInFlight.insert(post.uri).inserted else {
            logger.debug("repost ignored — already in-flight for \(post.uri.rawValue, privacy: .public)")
            return
        }
        defer { repostInFlight.remove(post.uri) }
        guard let did = await loadCurrentDID() else { return }
        let livePost = posts.first(where: { $0.post.uri == post.uri })?.post ?? post
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
            pendingRepostURIs[post.uri] = resp.uri
            updatePost(uri: post.uri) { $0.withRepost(resp.uri) }
        } catch {
            logger.error("repost failed for \(post.uri.rawValue, privacy: .public): \(error, privacy: .public)")
            updatePost(uri: post.uri) { $0.withRepost(nil) }
        }
        pendingRepostURIs.removeValue(forKey: post.uri)
        // defer removes repostInFlight entry.
    }

    public func unrepost(post: PostView) async {
        guard let repostURI = post.viewer?.repost else { return }
        // Claim the slot synchronously before any await.
        guard repostInFlight.insert(post.uri).inserted else {
            logger.debug("unrepost ignored — already in-flight for \(post.uri.rawValue, privacy: .public)")
            return
        }
        defer { repostInFlight.remove(post.uri) }
        guard let did = await loadCurrentDID(),
              let rkey = repostURI.rkey else { return }
        updatePost(uri: post.uri) { $0.withRepost(nil) }
        do {
            let req = DeleteRecordRequest(repo: did.rawValue, collection: "app.bsky.feed.repost", rkey: rkey)
            let _: EmptyResponse = try await network.post(lexicon: "com.atproto.repo.deleteRecord", body: req)
            logger.debug("unrepost succeeded for \(post.uri.rawValue, privacy: .public)")
        } catch {
            logger.error("unrepost failed for \(post.uri.rawValue, privacy: .public): \(error, privacy: .public)")
            updatePost(uri: post.uri) { $0.withRepost(repostURI) }
        }
        // defer removes repostInFlight entry.
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
        try? await accountStore.loadCurrentDID()
    }

    private func updatePost(uri: ATURI, transform: (PostView) -> PostView) {
        guard let idx = posts.firstIndex(where: { $0.post.uri == uri }) else { return }
        let old = posts[idx]
        posts[idx] = FeedViewPost(post: transform(old.post), reply: old.reply, reason: old.reason)
    }
}
