import SwiftUI
import BlueskyCore
import BlueskyKit
import BlueskyUI

public struct BookmarksScreen: View {
    private let store: any BookmarksStoring

    public init(store: any BookmarksStoring) {
        self.store = store
    }

    public var body: some View {
        Group {
            if store.isLoading && store.bookmarks.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.bookmarks.isEmpty {
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

    private var bookmarkList: some View {
        List {
            ForEach(store.bookmarks, id: \.uri) { bookmark in
                PostCard(
                    item: FeedViewPost(post: bookmark.item, reply: nil, reason: nil),
                    actions: actions(for: bookmark)
                )
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .onAppear {
                    if bookmark.uri == store.bookmarks.last?.uri {
                        Task { await store.loadMore() }
                    }
                }
            }
            if store.isLoadingMore {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Helpers

    private func actions(for bookmark: BookmarkView) -> PostCard.Actions {
        var a = PostCard.Actions()
        a.isBookmarked = true
        a.onBookmark = { _ in
            Task { await store.delete(bookmarkURI: bookmark.uri) }
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
    func delete(bookmarkURI: ATURI) async {}
    func clearError() {}
}

#Preview("BookmarksScreen — Empty") {
    NavigationStack {
        BookmarksScreen(store: PreviewBookmarksStore())
    }
    .preferredColorScheme(.light)
}
