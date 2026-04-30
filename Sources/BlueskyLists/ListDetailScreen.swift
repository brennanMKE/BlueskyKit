import SwiftUI
import BlueskyCore
import BlueskyKit
import BlueskyUI

private final class PreviewNoOpNetwork: NetworkClient, @unchecked Sendable {
    nonisolated func get<R: Decodable & Sendable>(lexicon: String, params: [String: String]) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func post<B: Encodable & Sendable, R: Decodable & Sendable>(lexicon: String, body: B) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func upload<R: Decodable & Sendable>(lexicon: String, data: Data, mimeType: String) async throws -> R { throw ATError.unknown("preview") }
}

struct ListDetailScreen: View {

    @State private var viewModel: ListDetailViewModel
    @State private var selectedTab = 0
    private let listURI: ATURI

    init(listURI: ATURI, network: any NetworkClient) {
        self.listURI = listURI
        _viewModel = State(initialValue: ListDetailViewModel(network: network))
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Tab", selection: $selectedTab) {
                Text("Members").tag(0)
                Text("Feed").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            if selectedTab == 0 {
                membersTab
            } else {
                feedTab
            }
        }
        .navigationTitle(viewModel.list?.name ?? "List")
        .overlay {
            if viewModel.isLoading && viewModel.list == nil {
                ProgressView()
            }
        }
        .task { await viewModel.load(listURI: listURI) }
        .onChange(of: selectedTab) { _, newValue in
            if newValue == 1 && viewModel.feed.isEmpty {
                Task { await viewModel.loadFeed() }
            }
        }
    }

    // MARK: - Members Tab

    private var membersTab: some View {
        List {
            if viewModel.members.isEmpty && !viewModel.isLoading {
                ContentUnavailableView(
                    "No Members",
                    systemImage: "person.3",
                    description: Text("This list has no members yet.")
                )
            } else {
                ForEach(viewModel.members, id: \.uri) { item in
                    MemberRow(item: item)
                        .onAppear {
                            if item.uri == viewModel.members.last?.uri {
                                Task { await viewModel.loadMore() }
                            }
                        }
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Feed Tab

    private var feedTab: some View {
        List {
            if viewModel.feed.isEmpty && !viewModel.isLoading {
                ContentUnavailableView(
                    "No Posts",
                    systemImage: "text.bubble",
                    description: Text("No posts from list members yet.")
                )
            } else {
                ForEach(viewModel.feed, id: \.post.uri) { feedPost in
                    PostCard(item: feedPost)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .onAppear {
                            if feedPost.post.uri == viewModel.feed.last?.post.uri {
                                Task { await viewModel.loadMoreFeed() }
                            }
                        }
                }
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - MemberRow

private struct MemberRow: View {
    let item: ListItemView

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(url: item.subject.avatar, handle: item.subject.handle.rawValue, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                if let displayName = item.subject.displayName, !displayName.isEmpty {
                    Text(displayName)
                        .font(.headline)
                        .lineLimit(1)
                }
                Text("@\(item.subject.handle.rawValue)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let desc = item.subject.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Previews

#Preview("ListDetailScreen — Light") {
    NavigationStack {
        ListDetailScreen(
            listURI: ATURI(rawValue: "at://did:plc:alice/app.bsky.graph.list/abc"),
            network: PreviewNoOpNetwork()
        )
    }
    .preferredColorScheme(.light)
}

#Preview("ListDetailScreen — Dark") {
    NavigationStack {
        ListDetailScreen(
            listURI: ATURI(rawValue: "at://did:plc:alice/app.bsky.graph.list/abc"),
            network: PreviewNoOpNetwork()
        )
    }
    .preferredColorScheme(.dark)
}
