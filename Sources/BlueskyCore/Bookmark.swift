import Foundation

// MARK: - app.bsky.bookmark.defs#bookmarkView
//
// Wire shape (per AT Proto `app.bsky.bookmark.defs#bookmarkView` and confirmed
// against the React Native client at
// `Bluesky-ReactNative/src/state/queries/bookmarks/useBookmarksQuery.ts`):
//
//     {
//       "subject":   { "uri": "at://...", "cid": "bafy..." },   // strong ref to the bookmarked post
//       "createdAt": "2026-05-07T12:00:00Z",
//       "item":      { "$type": "app.bsky.feed.defs#postView", ... } // hydrated post
//     }
//
// The bookmark item itself does **not** carry a top-level `uri`; that lives
// on `subject.uri`. Earlier versions of this struct decoded `uri`/`cid` at the
// top level, which crashed against the live response (issue #0152).

/// Strong reference to the bookmarked record (post URI + CID).
///
/// Mirrors the AT Proto `com.atproto.repo.strongRef` shape that the bookmark
/// lexicon nests under the `subject` key.
public struct BookmarkSubject: Codable, Sendable, Equatable {
    public let uri: ATURI
    public let cid: CID

    public init(uri: ATURI, cid: CID) {
        self.uri = uri
        self.cid = cid
    }
}

/// One bookmarked post as returned by `app.bsky.bookmark.getBookmarks`.
public struct BookmarkView: Codable, Sendable {
    /// Strong reference (uri + cid) to the bookmarked post.
    public let subject: BookmarkSubject
    /// When the bookmark was created.
    public let createdAt: Date
    /// The hydrated post view. Optional because the lexicon allows
    /// the post to be unresolved (e.g. deleted by author) — RN treats `item`
    /// as an open union but in practice it carries `app.bsky.feed.defs#postView`.
    public let item: PostView?

    public init(subject: BookmarkSubject, createdAt: Date, item: PostView?) {
        self.subject = subject
        self.createdAt = createdAt
        self.item = item
    }

    /// Convenience accessor for the bookmarked post's AT-URI. Equivalent to
    /// `subject.uri` — exposed so call sites that previously read
    /// `bookmark.uri` keep working without reaching into the nested ref.
    public var uri: ATURI { subject.uri }

    /// Convenience accessor for the bookmarked post's CID.
    public var cid: CID { subject.cid }
}

// MARK: - app.bsky.bookmark.getBookmarks

public struct GetBookmarksResponse: Decodable, Sendable {
    public let bookmarks: [BookmarkView]
    public let cursor: String?

    public init(bookmarks: [BookmarkView], cursor: String?) {
        self.bookmarks = bookmarks
        self.cursor = cursor
    }
}

// MARK: - app.bsky.bookmark.createBookmark

public struct CreateBookmarkRequest: Encodable, Sendable {
    public let uri: String
    public let cid: String

    public init(post: PostView) {
        self.uri = post.uri.rawValue
        self.cid = post.cid
    }

    public init(uri: ATURI, cid: CID) {
        self.uri = uri.rawValue
        self.cid = cid
    }
}

// MARK: - app.bsky.bookmark.deleteBookmark

public struct DeleteBookmarkRequest: Encodable, Sendable {
    public let uri: String

    /// Pass the **post's** AT-URI (the same value as `BookmarkView.subject.uri`).
    /// The lexicon takes the bookmarked post's URI, not a separate bookmark
    /// record URI — confirmed against
    /// `Bluesky-ReactNative/src/state/queries/bookmarks/useBookmarkMutation.ts`.
    public init(postURI: ATURI) { self.uri = postURI.rawValue }

    /// Back-compat shim: existing call sites used `bookmarkURI:` even though
    /// the value is the post URI. Kept so older callers compile while we
    /// rename them.
    @available(*, deprecated, renamed: "init(postURI:)", message: "The argument is the post's AT-URI, not a bookmark record URI.")
    public init(bookmarkURI: ATURI) { self.uri = bookmarkURI.rawValue }
}
