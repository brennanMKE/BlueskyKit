import Foundation
import Observation
import BlueskyCore
import BlueskyKit

/// View-model that exposes bookmark state from a `BookmarkStoring` implementation.
///
/// Thin wrapper so that `BookmarksScreen` does not need to reference
/// the concrete `BookmarkStore` type from `BlueskyDataStore`.
@Observable
public final class BookmarksViewModel {
    /// The snapshot list, ordered newest bookmark first.
    public var bookmarks: [BookmarkedPostSnapshot] { store.bookmarks }

    private let store: any BookmarkStoring

    public init(store: any BookmarkStoring) {
        self.store = store
    }

    public func isBookmarked(uri: String) -> Bool {
        store.isBookmarked(uri: uri)
    }

    public func toggle(post: PostView) {
        store.toggle(post: post)
    }
}
