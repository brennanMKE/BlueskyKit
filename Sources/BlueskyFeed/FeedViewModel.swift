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

    public var posts: [FeedViewPost] { store.posts }
    public var isLoading: Bool { store.isLoading }
    public var isRefreshing = false
    public var errorMessage: String? { store.errorMessage }

    private let store: any FeedStoring
    private let selection: FeedSelection

    public init(
        network: any NetworkClient,
        accountStore: any AccountStore,
        cache: any CacheStore,
        selection: FeedSelection = .timeline
    ) {
        self.store = FeedStore(network: network, accountStore: accountStore, cache: cache)
        self.selection = selection
    }

    // MARK: - Loading

    public func loadInitial() async {
        await store.loadInitial(selection: selection)
    }

    public func loadMore() async {
        await store.loadMore(selection: selection)
    }

    public func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await store.refresh(selection: selection)
    }

    // MARK: - Interactions

    public func like(post: PostView) async {
        await store.like(post: post)
    }

    public func unlike(post: PostView) async {
        await store.unlike(post: post)
    }

    public func repost(post: PostView) async {
        await store.repost(post: post)
    }

    public func unrepost(post: PostView) async {
        await store.unrepost(post: post)
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
