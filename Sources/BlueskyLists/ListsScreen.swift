import SwiftUI
import BlueskyCore
import BlueskyKit
import BlueskyUI

public struct ListsScreen: View {

    @State private var viewModel: ListsViewModel
    @State private var showCreateSheet = false
    private let actorDID: String
    private let network: any NetworkClient

    public init(actorDID: String, network: any NetworkClient, accountStore: any AccountStore) {
        self.actorDID = actorDID
        self.network = network
        _viewModel = State(initialValue: ListsViewModel(network: network, accountStore: accountStore))
    }

    public var body: some View {
        List {
            if viewModel.lists.isEmpty && !viewModel.isLoading {
                ContentUnavailableView(
                    "No Lists",
                    systemImage: "list.bullet",
                    description: Text("Lists you create will appear here.")
                )
            } else {
                ForEach(viewModel.lists, id: \.uri) { list in
                    NavigationLink {
                        ListDetailScreen(listURI: list.uri, network: network)
                    } label: {
                        ListRow(list: list)
                    }
                    .onAppear {
                        if list.uri == viewModel.lists.last?.uri {
                            Task { await viewModel.loadMore(actorDID: actorDID) }
                        }
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let list = viewModel.lists[index]
                        Task { await viewModel.deleteList(uri: list.uri) }
                    }
                }
            }
        }
        .navigationTitle("Lists")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            ListCreateSheet { name, purpose, description in
                Task {
                    await viewModel.createList(name: name, description: description, purpose: purpose)
                }
                showCreateSheet = false
            }
        }
        .overlay {
            if viewModel.isLoading && viewModel.lists.isEmpty {
                ProgressView()
            }
        }
        .refreshable { await viewModel.loadLists(actorDID: actorDID) }
        .task { await viewModel.loadLists(actorDID: actorDID) }
    }
}

// MARK: - ListRow

private struct ListRow: View {
    let list: ListView

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(url: list.avatar, handle: list.name, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(list.name)
                        .font(.headline)
                        .lineLimit(1)
                    PurposeBadge(purpose: list.purpose)
                }
                Text("by @\(list.creator.handle.rawValue)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let desc = list.description, !desc.isEmpty {
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

// MARK: - PurposeBadge

private struct PurposeBadge: View {
    let purpose: String

    private var label: String {
        purpose == "app.bsky.graph.defs#modlist" ? "MOD" : "Curated"
    }

    private var color: Color {
        purpose == "app.bsky.graph.defs#modlist" ? .orange : .blue
    }

    var body: some View {
        Text(label)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
