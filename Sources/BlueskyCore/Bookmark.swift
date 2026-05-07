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
//       "item":      { "$type": "app.bsky.feed.defs#postView", ... } // hydrated post (open union)
//     }
//
// The bookmark item itself does **not** carry a top-level `uri`; that lives
// on `subject.uri`. Earlier versions of this struct decoded `uri`/`cid` at the
// top level, which crashed against the live response (issue #0152).
//
// `item` is a **discriminated union** keyed on `$type`:
//   - `app.bsky.feed.defs#postView`     — a normal hydrated post.
//   - `app.bsky.feed.defs#notFoundPost` — the post was deleted by its author.
//   - `app.bsky.feed.defs#blockedPost`  — the viewer is blocked from / has
//                                         blocked the post's author.
// Any other `$type` lands as `.unknown` so a future server addition can't
// re-break decoding (issue #0154).

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

// MARK: - Bookmark item variants (`bookmarkView.item` open union)

/// Tombstone for `app.bsky.feed.defs#notFoundPost` — the post was deleted by
/// its author. The lexicon carries `{uri, notFound: true}`; on the actor view
/// inside the bookmarks list there is no embedded `author`, so we keep
/// `author` optional to match the open-union shape.
public struct NotFoundPost: Codable, Sendable, Equatable {
    public let uri: ATURI
    public let notFound: Bool
    public let author: ProfileBasic?

    public init(uri: ATURI, notFound: Bool = true, author: ProfileBasic? = nil) {
        self.uri = uri
        self.notFound = notFound
        self.author = author
    }

    private enum CodingKeys: String, CodingKey {
        case uri, notFound, author
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uri = try c.decode(ATURI.self, forKey: .uri)
        notFound = try c.decodeIfPresent(Bool.self, forKey: .notFound) ?? true
        author = try c.decodeIfPresent(ProfileBasic.self, forKey: .author)
    }
}

/// Tombstone for `app.bsky.feed.defs#blockedPost` — the post is from a
/// blocked account (or the viewer is blocked). Lexicon shape is
/// `{uri, blocked: true, author: blockedAuthor}` where `blockedAuthor` is a
/// minimal profile reference.
public struct BlockedPost: Codable, Sendable, Equatable {
    public let uri: ATURI
    public let blocked: Bool
    /// Minimal profile reference for the blocked author. Optional because the
    /// AppView occasionally omits it on partial views.
    public let author: ProfileBasic?

    public init(uri: ATURI, blocked: Bool = true, author: ProfileBasic? = nil) {
        self.uri = uri
        self.blocked = blocked
        self.author = author
    }

    private enum CodingKeys: String, CodingKey {
        case uri, blocked, author
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uri = try c.decode(ATURI.self, forKey: .uri)
        blocked = try c.decodeIfPresent(Bool.self, forKey: .blocked) ?? true
        author = try c.decodeIfPresent(ProfileBasic.self, forKey: .author)
    }
}

/// Open-union view over the hydrated `bookmarkView.item` field.
///
/// Mirrors RN's `BookmarkView["item"]` (see
/// `Bluesky-ReactNative/src/screens/Bookmarks/index.tsx`, which switches on
/// `AppBskyFeedDefs.isNotFoundPost` / `AppBskyFeedDefs.isPostView`). The
/// `unknown` case absorbs any future variant the server adds without
/// breaking the entire bookmarks page (issue #0154). The shape mirrors the
/// `ThreadViewPost` open-union pattern in `Feed.swift`.
public enum BookmarkItemView: Sendable {
    case post(PostView)
    case notFound(NotFoundPost)
    case blocked(BlockedPost)
    /// Unsupported `$type` — render as a generic tombstone rather than aborting decode.
    case unknown(String)
}

extension BookmarkItemView: Decodable {
    private enum CodingKeys: String, CodingKey { case type = "$type" }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "app.bsky.feed.defs#postView":
            self = .post(try PostView(from: decoder))
        case "app.bsky.feed.defs#notFoundPost":
            self = .notFound(try NotFoundPost(from: decoder))
        case "app.bsky.feed.defs#blockedPost":
            self = .blocked(try BlockedPost(from: decoder))
        default:
            self = .unknown(type)
        }
    }
}

extension BookmarkItemView: Encodable {
    public func encode(to encoder: any Encoder) throws {
        // Encode the inner payload directly. We don't always have a `$type`
        // for the .post case (PostView's existing Codable doesn't write it),
        // but bookmarks are read-only on the wire — encoding is exercised by
        // round-trip tests, not by API requests. Round-trip back through
        // `BookmarkItemView` works because the outer caller writes `$type`
        // explicitly when constructing fixtures (or via the structured
        // encoder containers below).
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .post(let p):
            try c.encode("app.bsky.feed.defs#postView", forKey: .type)
            try p.encode(to: encoder)
        case .notFound(let n):
            try c.encode("app.bsky.feed.defs#notFoundPost", forKey: .type)
            try n.encode(to: encoder)
        case .blocked(let b):
            try c.encode("app.bsky.feed.defs#blockedPost", forKey: .type)
            try b.encode(to: encoder)
        case .unknown(let t):
            try c.encode(t, forKey: .type)
        }
    }
}

// MARK: - bookmarkView

/// One bookmarked post as returned by `app.bsky.bookmark.getBookmarks`.
public struct BookmarkView: Codable, Sendable {
    /// Strong reference (uri + cid) to the bookmarked post.
    public let subject: BookmarkSubject
    /// When the bookmark was created.
    public let createdAt: Date
    /// The hydrated post view, as a discriminated union over
    /// `postView` / `notFoundPost` / `blockedPost` / unknown.
    /// Optional because the lexicon allows the server to omit the field
    /// for unresolved bookmarks.
    public let item: BookmarkItemView?

    public init(subject: BookmarkSubject, createdAt: Date, item: BookmarkItemView?) {
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

    private enum CodingKeys: String, CodingKey {
        case bookmarks, cursor
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cursor = try c.decodeIfPresent(String.self, forKey: .cursor)

        // Decode the bookmarks array defensively: a single malformed item
        // (e.g. a future variant that decodes to `.unknown` but whose outer
        // bookmark envelope we can't parse) must not abort the entire page.
        // RN's bookmarks query also tolerates per-item failures client-side.
        // Unknown `$type` values inside `item` are already absorbed by
        // `BookmarkItemView.unknown`; this handles the outer envelope too.
        var nested = try c.nestedUnkeyedContainer(forKey: .bookmarks)
        var collected: [BookmarkView] = []
        if let count = nested.count {
            collected.reserveCapacity(count)
        }
        while !nested.isAtEnd {
            do {
                let view = try nested.decode(BookmarkView.self)
                collected.append(view)
            } catch {
                // Advance past the bad element without failing the whole
                // response. JSONDecoder requires we consume the slot, so we
                // decode it as an opaque value that always succeeds.
                _ = try? nested.decode(_AnyValue.self)
            }
        }
        bookmarks = collected
    }
}

/// Internal opaque-decode helper used by `GetBookmarksResponse` to skip past
/// a bookmark element that failed to decode without leaving the unkeyed
/// container in an inconsistent state.
private struct _AnyValue: Decodable {
    init(from decoder: any Decoder) throws {
        // `singleValueContainer().decodeNil()` will succeed for any payload
        // by examining + advancing the underlying cursor. Falling through to
        // a JSON-aware decode keeps non-null values from getting stuck.
        if let single = try? decoder.singleValueContainer(), single.decodeNil() {
            return
        }
        // Try keyed / unkeyed / single in turn — at least one will succeed
        // for any valid JSON payload, advancing the parent unkeyed container.
        if let keyed = try? decoder.container(keyedBy: _AnyKey.self) {
            for key in keyed.allKeys {
                _ = try? keyed.decode(_AnyValue.self, forKey: key)
            }
            return
        }
        if var unkeyed = try? decoder.unkeyedContainer() {
            while !unkeyed.isAtEnd {
                _ = try? unkeyed.decode(_AnyValue.self)
            }
            return
        }
        // Single-value scalar: try common primitive types. Any one match is
        // enough to advance the cursor.
        let s = try decoder.singleValueContainer()
        if (try? s.decode(Bool.self)) != nil { return }
        if (try? s.decode(Double.self)) != nil { return }
        if (try? s.decode(String.self)) != nil { return }
    }

    private struct _AnyKey: CodingKey {
        let stringValue: String
        let intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue; self.intValue = nil }
        init?(intValue: Int) { self.intValue = intValue; self.stringValue = "\(intValue)" }
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
