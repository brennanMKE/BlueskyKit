import Foundation
import Observation
import BlueskyCore
import BlueskyKit

// MARK: - Feed selection

public enum FeedSelection: Hashable, Sendable {
    case timeline
    case feed(uri: String)
}

// MARK: - FeedViewModel

@Observable
public final class FeedViewModel {

    public var posts: [FeedViewPost] = []
    public var isLoading = false
    public var isRefreshing = false
    public var errorMessage: String?

    private var cursor: String?
    private var hasMore = true

    private let network: any NetworkClient
    private let accountStore: any AccountStore
    private let selection: FeedSelection

    public init(
        network: any NetworkClient,
        accountStore: any AccountStore,
        selection: FeedSelection = .timeline
    ) {
        self.network = network
        self.accountStore = accountStore
        self.selection = selection
    }

    // MARK: - Loading

    public func loadInitial() async {
        guard !isLoading, posts.isEmpty else { return }
        await fetch(reset: false)
    }

    public func loadMore() async {
        guard !isLoading, hasMore else { return }
        await fetch(reset: false)
    }

    public func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await fetch(reset: true)
    }

    private func fetch(reset: Bool) async {
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
                response = try await network.get(
                    lexicon: "app.bsky.feed.getTimeline",
                    params: params
                )
            case .feed(let uri):
                params["feed"] = uri
                response = try await network.get(
                    lexicon: "app.bsky.feed.getFeed",
                    params: params
                )
            }
            cursor = response.cursor
            hasMore = response.cursor != nil
            if reset {
                posts = response.feed
            } else {
                posts.append(contentsOf: response.feed)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Interactions

    public func like(post: PostView) async {
        guard let did = await loadCurrentDID() else { return }
        let wasLiked = post.viewer?.like != nil
        guard !wasLiked else { return }
        updatePost(uri: post.uri) { $0.withLike(ATURI(rawValue: "pending://like")) }
        do {
            let req = CreateRecordRequest(
                repo: did.rawValue,
                collection: "app.bsky.feed.like",
                record: LikeRecord(subject: PostRef(uri: post.uri, cid: post.cid))
            )
            let resp: CreateRecordResponse = try await network.post(
                lexicon: "com.atproto.repo.createRecord",
                body: req
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
            let req = DeleteRecordRequest(
                repo: did.rawValue,
                collection: "app.bsky.feed.like",
                rkey: rkey
            )
            let _: EmptyResponse = try await network.post(
                lexicon: "com.atproto.repo.deleteRecord",
                body: req
            )
        } catch {
            updatePost(uri: post.uri) { $0.withLike(likeURI) }
        }
    }

    public func repost(post: PostView) async {
        guard let did = await loadCurrentDID() else { return }
        let wasReposted = post.viewer?.repost != nil
        guard !wasReposted else { return }
        updatePost(uri: post.uri) { $0.withRepost(ATURI(rawValue: "pending://repost")) }
        do {
            let req = CreateRecordRequest(
                repo: did.rawValue,
                collection: "app.bsky.feed.repost",
                record: RepostRecord(subject: PostRef(uri: post.uri, cid: post.cid))
            )
            let resp: CreateRecordResponse = try await network.post(
                lexicon: "com.atproto.repo.createRecord",
                body: req
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
            let req = DeleteRecordRequest(
                repo: did.rawValue,
                collection: "app.bsky.feed.repost",
                rkey: rkey
            )
            let _: EmptyResponse = try await network.post(
                lexicon: "com.atproto.repo.deleteRecord",
                body: req
            )
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

// MARK: - PostView mutation helpers (optimistic updates)

extension PostView {
    func withLike(_ likeURI: ATURI?) -> PostView {
        let wasLiked = viewer?.like != nil
        let newCount = wasLiked && likeURI == nil ? max(0, likeCount - 1)
                     : !wasLiked && likeURI != nil ? likeCount + 1
                     : likeCount
        let v = PostViewerState(
            like: likeURI,
            repost: viewer?.repost,
            threadMuted: viewer?.threadMuted,
            replyDisabled: viewer?.replyDisabled
        )
        return PostView(
            uri: uri, cid: cid, author: author, record: record, embed: embed,
            replyCount: replyCount, repostCount: repostCount,
            likeCount: newCount, quoteCount: quoteCount,
            indexedAt: indexedAt, labels: labels, viewer: v
        )
    }

    func withRepost(_ repostURI: ATURI?) -> PostView {
        let wasReposted = viewer?.repost != nil
        let newCount = wasReposted && repostURI == nil ? max(0, repostCount - 1)
                     : !wasReposted && repostURI != nil ? repostCount + 1
                     : repostCount
        let v = PostViewerState(
            like: viewer?.like,
            repost: repostURI,
            threadMuted: viewer?.threadMuted,
            replyDisabled: viewer?.replyDisabled
        )
        return PostView(
            uri: uri, cid: cid, author: author, record: record, embed: embed,
            replyCount: replyCount, repostCount: newCount,
            likeCount: likeCount, quoteCount: quoteCount,
            indexedAt: indexedAt, labels: labels, viewer: v
        )
    }
}
