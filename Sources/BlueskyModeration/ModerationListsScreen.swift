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
            if viewModel.modLists.isEmpty
                && viewModel.subscribedModLists.isEmpty
                && !viewModel.isLoading {
                ContentUnavailableView(
                    "No Moderation Lists",
                    systemImage: "list.bullet.clipboard",
                    description: Text("Public, sharable lists of users to mute or block in bulk.")
                )
            } else {
                // "My moderation lists" — lists the viewer authored. Mirrors
                // RN's `MyLists filter="mod"` rows where the list's creator
                // matches the signed-in account. Edit/delete affordances live
                // inside the list detail screen.
                Section("My moderation lists") {
                    ownedSection
                }

                // "Subscribed" — mod lists the viewer subscribed to without
                // owning. Drawn from `getListMutes` / `getListBlocks` and
                // filtered to lists where `creator.did != viewerDID`. Per-row
                // action is Unsubscribe (calls `unmuteActorList` for muted,
                // deletes the `listblock` record for blocked).
                Section("Subscribed") {
                    subscribedSection
                }
            }
        }
        .navigationTitle("Moderation Lists")
        .refreshable {
            await viewModel.resolveViewerDID()
            await viewModel.loadModLists()
        }
        .task {
            await viewModel.resolveViewerDID()
            await viewModel.loadModLists()
        }
        .overlay {
            if viewModel.isLoading
                && viewModel.modLists.isEmpty
                && viewModel.subscribedModLists.isEmpty {
                ProgressView()
            }
        }
    }

    // MARK: - Sections

    /// Rows for mod lists the viewer authored. Tail-of-section pagination
    /// fires `loadMoreModLists` (paginates the underlying `getLists` cursor).
    @ViewBuilder
    private var ownedSection: some View {
        let owned = viewModel.modLists
        if owned.isEmpty {
            Text("Moderation lists you create will appear here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            ForEach(owned, id: \.uri) { list in
                ModListRow(list: list, action: .none)
                    .onAppear {
                        if list.uri == owned.last?.uri {
                            Task { await viewModel.loadMoreModLists() }
                        }
                    }
            }
        }
    }

    /// Rows for mod lists the viewer subscribed to. Per-row Unsubscribe
    /// button picks `unmuteActorList` (for muted lists) or
    /// `deleteRecord(listblock)` (for blocked lists), matching RN's
    /// `useListMuteMutation` / `useListBlockMutation` split.
    @ViewBuilder
    private var subscribedSection: some View {
        let subscribed = viewModel.subscribedModLists
        if subscribed.isEmpty {
            Text("Subscribed mod lists will appear here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            ForEach(subscribed, id: \.uri) { list in
                ModListRow(list: list, action: .unsubscribe {
                    Task { await viewModel.unsubscribe(from: list) }
                })
                .onAppear {
                    if list.uri == subscribed.last?.uri && viewModel.hasMoreSubscribedModLists {
                        Task { await viewModel.loadMoreSubscribedModLists() }
                    }
                }
            }
        }
    }
}

// MARK: - ModListRow

private enum ModListRowAction {
    case none
    case unsubscribe(() -> Void)
}

private struct ModListRow: View {
    let list: ListView
    let action: ModListRowAction

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

            switch action {
            case .none:
                EmptyView()
            case .unsubscribe(let onUnsubscribe):
                Button("Unsubscribe", role: .destructive) { onUnsubscribe() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
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
