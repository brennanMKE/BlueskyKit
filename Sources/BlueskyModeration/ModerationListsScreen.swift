import SwiftUI
import BlueskyCore
import BlueskyKit
import BlueskyUI

private final class PreviewNoOpNetwork: NetworkClient, @unchecked Sendable {
    nonisolated func get<R: Decodable & Sendable>(lexicon: String, params: [String: String]) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func post<B: Encodable & Sendable, R: Decodable & Sendable>(lexicon: String, body: B) async throws -> R { throw ATError.unknown("preview") }
    nonisolated func upload<R: Decodable & Sendable>(lexicon: String, data: Data, mimeType: String) async throws -> R { throw ATError.unknown("preview") }
}

private final class PreviewNoOpAccountStore: AccountStore, @unchecked Sendable {
    nonisolated func save(_ account: StoredAccount) async throws {}
    nonisolated func loadAll() async throws -> [StoredAccount] { [] }
    nonisolated func load(did: DID) async throws -> StoredAccount? { nil }
    nonisolated func remove(did: DID) async throws {}
    nonisolated func setCurrentDID(_ did: DID?) async throws {}
    nonisolated func loadCurrentDID() async throws -> DID? { nil }
}

public struct ModerationListsScreen: View {
    @State private var viewModel: ModerationViewModel

    public init(network: any NetworkClient, accountStore: any AccountStore) {
        _viewModel = State(initialValue: ModerationViewModel(network: network, accountStore: accountStore))
    }

    public var body: some View {
        List {
            if viewModel.modLists.isEmpty && !viewModel.isLoading {
                ContentUnavailableView(
                    "No Moderation Lists",
                    systemImage: "list.bullet.clipboard",
                    description: Text("Moderation lists you subscribe to will appear here.")
                )
            } else {
                ForEach(viewModel.modLists, id: \.uri) { list in
                    ModListRow(list: list) {
                        Task { await viewModel.unmuteList(list.uri) }
                    }
                    .onAppear {
                        if list.uri == viewModel.modLists.last?.uri {
                            Task { await viewModel.loadMoreModLists() }
                        }
                    }
                }
            }
        }
        .navigationTitle("Moderation Lists")
        .refreshable { await viewModel.loadModLists() }
        .task { await viewModel.loadModLists() }
        .overlay {
            if viewModel.isLoading && viewModel.modLists.isEmpty {
                ProgressView()
            }
        }
    }
}

// MARK: - ModListRow

private struct ModListRow: View {
    let list: ListView
    let onUnsubscribe: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(url: list.avatar, handle: list.name, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(list.name).font(.headline).lineLimit(1)
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

            Spacer()

            Button("Unsubscribe", role: .destructive) { onUnsubscribe() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Previews

#Preview("ModerationListsScreen — Light") {
    NavigationStack {
        ModerationListsScreen(
            network: PreviewNoOpNetwork(),
            accountStore: PreviewNoOpAccountStore()
        )
    }
    .preferredColorScheme(.light)
}

#Preview("ModerationListsScreen — Dark") {
    NavigationStack {
        ModerationListsScreen(
            network: PreviewNoOpNetwork(),
            accountStore: PreviewNoOpAccountStore()
        )
    }
    .preferredColorScheme(.dark)
}
