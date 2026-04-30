import Foundation
import OSLog
import Observation
import SwiftData
import BlueskyCore
import BlueskyKit

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "co.sstools.Bluesky",
    category: "BookmarkStore"
)

// MARK: - BookmarkStore

/// `@MainActor` SwiftData-backed implementation of `BookmarkStoring`.
///
/// All reads go through a query that is refreshed after every write,
/// keeping `bookmarks` in sync without requiring `@Query` (which is
/// view-only).  Inject a single shared instance at app startup.
@MainActor
@Observable
public final class BookmarkStore: BookmarkStoring {

    public private(set) var bookmarks: [BookmarkedPostSnapshot] = []

    private let container: ModelContainer

    // MARK: - Init

    /// Creates a persistent bookmark store.
    public init() throws {
        container = try Self.makeContainer(inMemory: false)
        refreshBookmarks()
    }

    /// Creates an in-memory store suitable for previews and tests.
    public static func inMemory() throws -> BookmarkStore {
        let store = try BookmarkStore(inMemory: true)
        return store
    }

    private init(inMemory: Bool) throws {
        container = try Self.makeContainer(inMemory: inMemory)
        refreshBookmarks()
    }

    private static func makeContainer(inMemory: Bool) throws -> ModelContainer {
        let schema = Schema([BookmarkedPost.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - BookmarkStoring

    public func isBookmarked(uri: String) -> Bool {
        bookmarks.contains { $0.uri == uri }
    }

    public func toggle(post: PostView) {
        let uriString = post.uri.rawValue
        if isBookmarked(uri: uriString) {
            remove(uri: uriString)
        } else {
            add(post: post)
        }
    }

    // MARK: - Private helpers

    private func add(post: PostView) {
        let ctx = ModelContext(container)
        let record = BookmarkedPost(
            uri: post.uri.rawValue,
            cid: post.cid,
            authorDID: post.author.did.rawValue,
            authorHandle: post.author.handle.rawValue,
            authorDisplayName: post.author.displayName,
            authorAvatarURL: post.author.avatar?.absoluteString,
            text: post.record.text,
            createdAt: post.record.createdAt
        )
        ctx.insert(record)
        do {
            try ctx.save()
            logger.info("bookmarked post \(post.uri.rawValue, privacy: .public)")
        } catch {
            logger.error("failed to bookmark post: \(error, privacy: .public)")
        }
        refreshBookmarks()
    }

    private func remove(uri: String) {
        let ctx = ModelContext(container)
        let target = uri
        do {
            try ctx.delete(model: BookmarkedPost.self, where: #Predicate { $0.uri == target })
            try ctx.save()
            logger.info("removed bookmark \(uri, privacy: .public)")
        } catch {
            logger.error("failed to remove bookmark: \(error, privacy: .public)")
        }
        refreshBookmarks()
    }

    private func refreshBookmarks() {
        let ctx = ModelContext(container)
        var descriptor = FetchDescriptor<BookmarkedPost>(
            sortBy: [SortDescriptor(\.bookmarkedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 500
        do {
            let results = try ctx.fetch(descriptor)
            bookmarks = results.map { post in
                BookmarkedPostSnapshot(
                    uri: post.uri,
                    cid: post.cid,
                    authorDID: post.authorDID,
                    authorHandle: post.authorHandle,
                    authorDisplayName: post.authorDisplayName,
                    authorAvatarURL: post.authorAvatarURL,
                    text: post.text,
                    createdAt: post.createdAt,
                    bookmarkedAt: post.bookmarkedAt
                )
            }
        } catch {
            logger.error("failed to fetch bookmarks: \(error, privacy: .public)")
            bookmarks = []
        }
    }
}
