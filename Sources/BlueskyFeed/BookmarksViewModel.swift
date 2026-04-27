import Foundation
import Observation
import BlueskyCore
import BlueskyKit

@Observable
public final class BookmarksViewModel {
    public var bookmarks: [BookmarkView] { store.bookmarks }
    public var isLoading: Bool { store.isLoading }
    public var isLoadingMore: Bool { store.isLoadingMore }
    public var error: String? { store.error }

    private let store: any BookmarksStoring

    public init(network: any NetworkClient) {
        self.store = BookmarksStore(network: network)
    }

    public func loadInitial() async { await store.loadInitial() }
    public func loadMore() async { await store.loadMore() }
    public func delete(bookmarkURI: ATURI) async { await store.delete(bookmarkURI: bookmarkURI) }
    public func clearError() { store.clearError() }
}
