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
                    row(for: bookmark)
                        .onAppear {
                            if bookmark.subject.uri == store.bookmarks.last?.subject.uri {
                                Task { await store.loadMore() }
                            }
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

    @ViewBuilder
    private func row(for bookmark: BookmarkView) -> some View {
        switch bookmark.item {
        case .post(let post):
            PostCard(
                item: FeedViewPost(post: post, reply: nil, reason: nil),
                actions: actions(for: bookmark)
            )
            Divider()
        case .notFound:
            // RN copy: "This post was deleted by its author".
            // See `Bluesky-ReactNative/src/screens/Bookmarks/index.tsx`
            // (`BookmarkNotFound`).
            tombstone(text: "This post was deleted by its author", bookmark: bookmark)
            Divider()
        case .blocked:
            tombstone(text: "This post is from a blocked account", bookmark: bookmark)
            Divider()
        case .unknown:
            tombstone(text: "Unsupported bookmark", bookmark: bookmark)
            Divider()
        case .none:
            // Server didn't hydrate this bookmark — keep the previous
            // skip-row behavior so the list stays compact.
            EmptyView()
        }
    }

    /// Compact tombstone row for non-`postView` bookmark items. Shows the
    /// reason and offers a "Remove" affordance so the user can clear the
    /// dead bookmark — mirrors RN's `BookmarkNotFound` component.
    private func tombstone(text: String, bookmark: BookmarkView) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 22))
                .foregroundStyle(theme.colors.textSecondary)
            Text(text)
                .font(.subheadline)
                .italic()
                .foregroundStyle(theme.colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Remove") {
                Task { await store.delete(postURI: bookmark.subject.uri) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
