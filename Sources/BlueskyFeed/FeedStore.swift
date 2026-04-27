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
        guard !isLoading, posts.isEmpty else { return }
        currentSelection = selection
        // Serve stale cache immediately, then refresh in background
        if let cached = try? await cache.fetch([FeedViewPost].self, for: cacheKey(selection)) {
            posts = cached.value
        }
        await fetch(selection: selection, reset: posts.isEmpty)
    }

    public func loadMore(selection: FeedSelection) async {
        guard !isLoading, hasMore else { return }
        await fetch(selection: selection, reset: false)
    }

    public func refresh(selection: FeedSelection) async {
        await fetch(selection: selection, reset: true)
    }

    private func fetch(selection: FeedSelection, reset: Bool) async {
        isLoading = true
        defer { isLoading = false }
        if reset { cursor = nil; hasMore = true }
        errorMessage = nil
        do {
            var params: [String: String] = ["limit": "50"]
            if let cursor { params["cursor"] = cursor }
            let response: FeedResponse
            switch selection {
            case .timeline:
                response = try await network.get(lexicon: "app.bsky.feed.getTimeline", params: params)
            case .feed(let uri):
                params["feed"] = uri
                response = try await network.get(lexicon: "app.bsky.feed.getFeed", params: params)
            }
            cursor = response.cursor
            hasMore = response.cursor != nil
            if reset {
                posts = response.feed
            } else {
                posts.append(contentsOf: response.feed)
            }
            // Cache first page only
            if reset {
                try? await cache.store(posts, for: cacheKey(selection), ttl: cacheTTL)
            }
        } catch {
            logger.error("fetch error: \(error, privacy: .public)")
            errorMessage = error.localizedDescription
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
        guard let did = await loadCurrentDID() else { return }
        guard post.viewer?.like == nil else { return }
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
            updatePost(uri: post.uri) { $0.withLike(resp.uri) }
        } catch {
            updatePost(uri: post.uri) { $0.withLike(nil) }
        }
    }

    public func unlike(post: PostView) async {
        guard let likeURI = post.viewer?.like,
              let did = await loadCurrentDID(),
              let rkey = likeURI.rkey else { return }
        updatePost(uri: post.uri) { $0.withLike(nil) }
        do {
            let req = DeleteRecordRequest(repo: did.rawValue, collection: "app.bsky.feed.like", rkey: rkey)
            let _: EmptyResponse = try await network.post(lexicon: "com.atproto.repo.deleteRecord", body: req)
        } catch {
            updatePost(uri: post.uri) { $0.withLike(likeURI) }
        }
    }

    public func repost(post: PostView) async {
        guard let did = await loadCurrentDID() else { return }
        guard post.viewer?.repost == nil else { return }
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
            updatePost(uri: post.uri) { $0.withRepost(resp.uri) }
        } catch {
            updatePost(uri: post.uri) { $0.withRepost(nil) }
        }
    }

    public func unrepost(post: PostView) async {
        guard let repostURI = post.viewer?.repost,
              let did = await loadCurrentDID(),
              let rkey = repostURI.rkey else { return }
        updatePost(uri: post.uri) { $0.withRepost(nil) }
        do {
            let req = DeleteRecordRequest(repo: did.rawValue, collection: "app.bsky.feed.repost", rkey: rkey)
            let _: EmptyResponse = try await network.post(lexicon: "com.atproto.repo.deleteRecord", body: req)
        } catch {
            updatePost(uri: post.uri) { $0.withRepost(repostURI) }
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
