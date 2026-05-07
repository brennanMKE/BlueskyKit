import SwiftUI
import BlueskyCore
import BlueskyKit
import BlueskyUI

/// Screen that lists the signed-in account's saved (bookmarked) posts.
///
/// Visual parity target: the bsky.app web "Saved" view — full post cards in a
/// scrollable feed, pull-to-refresh, infinite scroll, and tap to open the
/// thread or the author's profile. Optimistic removal happens via
/// `BookmarksStore.delete`.
public struct BookmarksScreen: View {
    private let store: any BookmarksStoring
    private let onPostTap: ((PostView) -> Void)?
    private let onAuthorTap: ((ProfileBasic) -> Void)?

    @Environment(\.blueskyTheme) private var theme

    public init(
        store: any BookmarksStoring,
        onPostTap: ((PostView) -> Void)? = nil,
        onAuthorTap: ((ProfileBasic) -> Void)? = nil
    ) {
        self.store = store
        self.onPostTap = onPostTap
        self.onAuthorTap = onAuthorTap
    }

    public var body: some View {
        Group {
            if store.isLoading && store.bookmarks.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.bookmarks.isEmpty {
                emptyState
            } else {
                bookmarkList
            }
        }
        .navigationTitle("Saved")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await store.loadInitial() }
        .alert("Error", isPresented: Binding(
            get: { store.error != nil },
            set: { if !$0 { store.clearError() } }
        )) {
            Button("OK") { store.clearError() }
        } message: {
            Text(store.error ?? "")
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bookmark")
                .font(.system(size: 40))
                .foregroundStyle(theme.colors.textSecondary)
            Text("Nothing saved yet")
                .font(.headline)
                .foregroundStyle(theme.colors.textSecondary)
            Text("Posts you bookmark will appear here.")
                .font(.subheadline)
                .foregroundStyle(theme.colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - List

    private var bookmarkList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(store.bookmarks, id: \.subject.uri) { bookmark in
                    if let post = bookmark.item {
                        PostCard(
                            item: FeedViewPost(post: post, reply: nil, reason: nil),
                            actions: actions(for: bookmark)
                        )
                        .onAppear {
                            if bookmark.subject.uri == store.bookmarks.last?.subject.uri {
                                Task { await store.loadMore() }
                            }
                        }
                        Divider()
                    }
                }
                if store.isLoadingMore {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .padding()
                }
            }
        }
        .refreshable { await store.loadInitial() }
    }

    // MARK: - Helpers

    private func actions(for bookmark: BookmarkView) -> PostCard.Actions {
        var a = PostCard.Actions()
        a.onTap = onPostTap
        a.onAuthorTap = onAuthorTap
        a.isBookmarked = true
        a.onBookmark = { _ in
            Task { await store.delete(postURI: bookmark.subject.uri) }
        }
        return a
    }
}

// MARK: - Previews

private final class PreviewBookmarksStore: BookmarksStoring {
    var bookmarks: [BookmarkView] = []
    var isLoading = false
    var isLoadingMore = false
    var error: String? = nil
    func loadInitial() async {}
    func loadMore() async {}
    func delete(postURI: ATURI) async {}
    func clearError() {}
}

#Preview("BookmarksScreen — Empty") {
    NavigationStack {
        BookmarksScreen(store: PreviewBookmarksStore())
    }
    .preferredColorScheme(.light)
}
