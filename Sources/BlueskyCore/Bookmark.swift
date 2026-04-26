import Foundation

// MARK: - app.bsky.bookmark.defs#bookmarkView

public struct BookmarkView: Decodable, Sendable {
    public let uri: ATURI
    public let cid: CID
    /// The bookmarked post.
    public let item: PostView
}

// MARK: - app.bsky.bookmark.getBookmarks

public struct GetBookmarksResponse: Decodable, Sendable {
    public let bookmarks: [BookmarkView]
    public let cursor: String?
}

// MARK: - app.bsky.bookmark.createBookmark

public struct CreateBookmarkRequest: Encodable, Sendable {
    public let uri: String
    public let cid: String

    public init(post: PostView) {
        self.uri = post.uri.rawValue
        self.cid = post.cid
    }
}

// MARK: - app.bsky.bookmark.deleteBookmark

public struct DeleteBookmarkRequest: Encodable, Sendable {
    public let uri: String

    /// Pass the bookmark's own AT-URI (from `BookmarkView.uri`).
    public init(bookmarkURI: ATURI) { self.uri = bookmarkURI.rawValue }
}
