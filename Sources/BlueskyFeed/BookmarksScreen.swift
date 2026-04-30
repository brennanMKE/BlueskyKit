import SwiftUI
import BlueskyCore
import BlueskyKit
import BlueskyUI

public struct BookmarksScreen: View {
    @State private var viewModel: BookmarksViewModel

    public init(store: any BookmarkStoring) {
        _viewModel = State(initialValue: BookmarksViewModel(store: store))
    }

    public var body: some View {
        Group {
            if viewModel.bookmarks.isEmpty {
                ContentUnavailableView(
                    "No Bookmarks",
                    systemImage: "bookmark",
                    description: Text("Posts you bookmark will appear here.")
                )
            } else {
                bookmarkList
            }
        }
        .navigationTitle("Bookmarks")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var bookmarkList: some View {
        List {
            ForEach(viewModel.bookmarks, id: \.uri) { snapshot in
                PostCard(
                    item: feedViewPost(from: snapshot),
                    actions: actions(for: snapshot)
                )
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Helpers

    private func actions(for snapshot: BookmarkedPostSnapshot) -> PostCard.Actions {
        var a = PostCard.Actions()
        a.isBookmarked = true
        a.onBookmark = { post in viewModel.toggle(post: post) }
        return a
    }

    /// Reconstruct a minimal `FeedViewPost` from the stored snapshot so we can
    /// reuse `PostCard` for display without persisting the full `PostView` graph.
    private func feedViewPost(from s: BookmarkedPostSnapshot) -> FeedViewPost {
        let author = ProfileBasic(
            did: DID(rawValue: s.authorDID),
            handle: Handle(rawValue: s.authorHandle),
            displayName: s.authorDisplayName,
            avatar: s.authorAvatarURL.flatMap { URL(string: $0) }
        )
        let record = PostRecord(text: s.text, createdAt: s.createdAt)
        let post = PostView(
            uri: ATURI(rawValue: s.uri),
            cid: s.cid,
            author: author,
            record: record,
            embed: nil,
            replyCount: 0,
            repostCount: 0,
            likeCount: 0,
            quoteCount: 0,
            indexedAt: s.createdAt,
            viewer: nil
        )
        return FeedViewPost(post: post, reply: nil, reason: nil)
    }
}

// MARK: - Previews

private final class PreviewBookmarkStore: BookmarkStoring {
    var bookmarks: [BookmarkedPostSnapshot] = []
    func isBookmarked(uri: String) -> Bool { false }
    func toggle(post: PostView) {}
}

#Preview("BookmarksScreen — Empty") {
    NavigationStack {
        BookmarksScreen(store: PreviewBookmarkStore())
    }
    .preferredColorScheme(.light)
}

#Preview("BookmarksScreen — With Items") {
    let store = PreviewBookmarkStore()
    store.bookmarks = [
        BookmarkedPostSnapshot(
            uri: "at://did:plc:alice/app.bsky.feed.post/abc",
            cid: "bafyabc",
            authorDID: "did:plc:alice",
            authorHandle: "alice.bsky.social",
            authorDisplayName: "Alice",
            authorAvatarURL: nil,
            text: "Hello, bookmarks!",
            createdAt: Date(timeIntervalSinceNow: -3600),
            bookmarkedAt: Date()
        )
    ]
    return NavigationStack {
        BookmarksScreen(store: store)
    }
    .preferredColorScheme(.light)
}
