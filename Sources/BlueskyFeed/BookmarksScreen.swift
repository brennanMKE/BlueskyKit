import SwiftUI
import BlueskyCore
import BlueskyKit
import BlueskyUI

private final class PreviewNoOpNetwork: NetworkClient, @unchecked Sendable {
    nonisolated func get<R: Decodable & Sendable>(lexicon: String, params: [String: String]) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func post<B: Encodable & Sendable, R: Decodable & Sendable>(lexicon: String, body: B) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func upload<R: Decodable & Sendable>(lexicon: String, data: Data, mimeType: String) async throws -> R { throw ATError.unknown("preview") }
}

public struct BookmarksScreen: View {
    @State private var viewModel: BookmarksViewModel

    public init(network: any NetworkClient) {
        _viewModel = State(initialValue: BookmarksViewModel(network: network))
    }

    public var body: some View {
        Group {
            if viewModel.isLoading && viewModel.bookmarks.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.bookmarks.isEmpty && !viewModel.isLoading {
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
        .task { await viewModel.loadInitial() }
        .refreshable { await viewModel.loadInitial() }
        .alert("Error", isPresented: Binding(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.clearError() } }
        )) {
            Button("OK") { viewModel.clearError() }
        } message: {
            Text(viewModel.error ?? "")
        }
    }

    private var bookmarkList: some View {
        List {
            ForEach(viewModel.bookmarks, id: \.uri) { bookmark in
                PostCard(item: FeedViewPost(post: bookmark.item, reply: nil, reason: nil))
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await viewModel.delete(bookmarkURI: bookmark.uri) }
                        } label: {
                            Label("Remove", systemImage: "bookmark.slash")
                        }
                    }
                    .onAppear {
                        if bookmark.uri == viewModel.bookmarks.last?.uri {
                            Task { await viewModel.loadMore() }
                        }
                    }
            }

            if viewModel.isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - Previews

#Preview("BookmarksScreen — Light") {
    NavigationStack {
        BookmarksScreen(network: PreviewNoOpNetwork())
    }
    .preferredColorScheme(.light)
}

#Preview("BookmarksScreen — Dark") {
    NavigationStack {
        BookmarksScreen(network: PreviewNoOpNetwork())
    }
    .preferredColorScheme(.dark)
}
