import Foundation
import Observation
import BlueskyCore
import BlueskyKit

@Observable
public final class BookmarksViewModel {
    public var bookmarks: [BookmarkView] = []
    public var isLoading = false
    public var isLoadingMore = false
    public var error: String?

    private var cursor: String?
    private var hasMore = true
    private let network: any NetworkClient

    public init(network: any NetworkClient) {
        self.network = network
    }

    public func loadInitial() async {
        guard !isLoading else { return }
        isLoading = true
        cursor = nil
        hasMore = true
        defer { isLoading = false }
        do {
            let response: GetBookmarksResponse = try await network.get(
                lexicon: "app.bsky.bookmark.getBookmarks",
                params: [:]
            )
            bookmarks = response.bookmarks
            cursor = response.cursor
            hasMore = response.cursor != nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func loadMore() async {
        guard hasMore, !isLoadingMore, let cursor else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            var params: [String: String] = [:]
            params["cursor"] = cursor
            let response: GetBookmarksResponse = try await network.get(
                lexicon: "app.bsky.bookmark.getBookmarks",
                params: params
            )
            bookmarks.append(contentsOf: response.bookmarks)
            self.cursor = response.cursor
            hasMore = response.cursor != nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func delete(bookmarkURI: ATURI) async {
        bookmarks.removeAll { $0.uri == bookmarkURI }
        do {
            let _: EmptyResponse = try await network.post(
                lexicon: "app.bsky.bookmark.deleteBookmark",
                body: DeleteBookmarkRequest(bookmarkURI: bookmarkURI)
            )
        } catch {
            self.error = error.localizedDescription
        }
    }
}
