import Foundation
import BlueskyCore

/// Minimal snapshot of a bookmarked post, suitable for display without importing BlueskyFeed.
public struct BookmarkedPostSnapshot: Sendable {
    public let uri: String
    public let cid: String
    public let authorDID: String
    public let authorHandle: String
    public let authorDisplayName: String?
    public let authorAvatarURL: String?
    public let text: String
    public let createdAt: Date
    public let bookmarkedAt: Date

    public init(
        uri: String,
        cid: String,
        authorDID: String,
        authorHandle: String,
        authorDisplayName: String?,
        authorAvatarURL: String?,
        text: String,
        createdAt: Date,
        bookmarkedAt: Date
    ) {
        self.uri = uri
        self.cid = cid
        self.authorDID = authorDID
        self.authorHandle = authorHandle
        self.authorDisplayName = authorDisplayName
        self.authorAvatarURL = authorAvatarURL
        self.text = text
        self.createdAt = createdAt
        self.bookmarkedAt = bookmarkedAt
    }
}

/// Contract for local bookmark storage.
///
/// Implementations are `@MainActor` observable objects (e.g. backed by SwiftData).
/// `BlueskyFeed` screens reference this protocol rather than the concrete type so that
/// the layer boundary (DataStore → Feed) is respected.
@MainActor
public protocol BookmarkStoring: AnyObject {
    /// All bookmarked posts, ordered newest bookmark first.
    var bookmarks: [BookmarkedPostSnapshot] { get }

    /// Returns `true` if the post URI is currently bookmarked.
    func isBookmarked(uri: String) -> Bool

    /// Bookmarks the post if not already saved; removes it if already bookmarked.
    func toggle(post: PostView)
}
