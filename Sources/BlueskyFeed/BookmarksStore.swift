import Foundation
import OSLog
import Observation
import BlueskyCore
import BlueskyKit

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "co.sstools.Bluesky", category: "BookmarksStore")

// MARK: - BookmarksStoring

public protocol BookmarksStoring: AnyObject, Observable, Sendable {
    var bookmarks: [BookmarkView] { get }
    var isLoading: Bool { get }
    var isLoadingMore: Bool { get }
    var error: String? { get }

    func loadInitial() async
    func loadMore() async
    func delete(bookmarkURI: ATURI) async
    func clearError()
}

// MARK: - BookmarksStore

@Observable
public final class BookmarksStore: BookmarksStoring {

    public private(set) var bookmarks: [BookmarkView] = []
    public private(set) var isLoading = false
    public private(set) var isLoadingMore = false
    public private(set) var error: String?

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
                lexicon: "app.bsky.bookmark.getBookmarks", params: [:]
            )
            bookmarks = response.bookmarks
            cursor = response.cursor
            hasMore = response.cursor != nil
        } catch {
            logger.error("bookmarks fetch error: \(error, privacy: .public)")
            self.error = error.localizedDescription
        }
    }

    public func loadMore() async {
        guard hasMore, !isLoadingMore, let cursor else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let response: GetBookmarksResponse = try await network.get(
                lexicon: "app.bsky.bookmark.getBookmarks", params: ["cursor": cursor]
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

    public func clearError() {
        error = nil
    }
}
