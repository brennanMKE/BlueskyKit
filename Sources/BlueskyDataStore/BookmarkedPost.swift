import SwiftData
import Foundation

/// SwiftData model representing a locally bookmarked post.
///
/// Fields are stored as primitive Swift types (String/Date) rather than
/// Core types to keep `BlueskyDataStore` independent of higher-level modules.
@Model
public final class BookmarkedPost {
    @Attribute(.unique) public var uri: String
    public var cid: String
    public var authorDID: String
    public var authorHandle: String
    public var authorDisplayName: String?
    public var authorAvatarURL: String?
    public var text: String
    public var createdAt: Date
    public var bookmarkedAt: Date

    public init(
        uri: String,
        cid: String,
        authorDID: String,
        authorHandle: String,
        authorDisplayName: String?,
        authorAvatarURL: String?,
        text: String,
        createdAt: Date
    ) {
        self.uri = uri
        self.cid = cid
        self.authorDID = authorDID
        self.authorHandle = authorHandle
        self.authorDisplayName = authorDisplayName
        self.authorAvatarURL = authorAvatarURL
        self.text = text
        self.createdAt = createdAt
        self.bookmarkedAt = Date()
    }
}
