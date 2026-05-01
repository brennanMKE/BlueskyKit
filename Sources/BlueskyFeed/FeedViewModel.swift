import Foundation
import Observation
import BlueskyCore
import BlueskyKit

// MARK: - Feed selection

public enum FeedSelection: Hashable, Sendable {
    case timeline
    case feed(uri: String)
}

// MARK: - FeedFilter

public struct FeedFilter: Equatable, Sendable {
    public var hideReplies: Bool = false
    public var hideReposts: Bool = false

    public init(hideReplies: Bool = false, hideReposts: Bool = false) {
        self.hideReplies = hideReplies
        self.hideReposts = hideReposts
    }

    public var isActive: Bool { hideReplies || hideReposts }
}

// MARK: - FeedViewModel

@Observable
public final class FeedViewModel {

    public var posts: [FeedViewPost] { store.posts }
    public var isLoading: Bool { store.isLoading }
    public var isRefreshing = false
    public var errorMessage: String? { store.errorMessage }

    public var filter: FeedFilter = FeedFilter()

    public var filteredPosts: [FeedViewPost] {
        store.posts.filter { item in
            if filter.hideReposts, item.reason != nil { return false }
            if filter.hideReplies, item.reply != nil { return false }
            return true
        }
    }

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

    /// Wraps a store that is already owned and loaded externally (e.g. created in boot()).
    public init(store: any FeedStoring, selection: FeedSelection) {
        self.store = store
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

    public func bookmark(post: PostView) async {
        if post.viewer?.bookmarked == true {
            await store.unbookmark(post: post)
        } else {
            await store.bookmark(post: post)
        }
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
            replyDisabled: viewer?.replyDisabled,
            bookmarked: viewer?.bookmarked
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
            replyDisabled: viewer?.replyDisabled,
            bookmarked: viewer?.bookmarked
        )
        return PostView(
            uri: uri, cid: cid, author: author, record: record, embed: embed,
            replyCount: replyCount, repostCount: newCount,
            likeCount: likeCount, quoteCount: quoteCount,
            indexedAt: indexedAt, labels: labels, viewer: v
        )
    }

    func withBookmarked(_ bookmarked: Bool) -> PostView {
        let v = PostViewerState(
            like: viewer?.like,
            repost: viewer?.repost,
            threadMuted: viewer?.threadMuted,
            replyDisabled: viewer?.replyDisabled,
            bookmarked: bookmarked
        )
        return PostView(
            uri: uri, cid: cid, author: author, record: record, embed: embed,
            replyCount: replyCount, repostCount: repostCount,
            likeCount: likeCount, quoteCount: quoteCount,
            indexedAt: indexedAt, labels: labels, viewer: v
        )
    }
}
